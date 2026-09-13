#!/usr/bin/env python3
"""Exercise actual SPARC helper bodies with a deterministic timer interleaving.

The injected timer arrives at do_modify_softint entry: after the caller has
computed its update, before the old implementation stores it. No probabilistic
thread scheduling is needed to demonstrate that lost-update window.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

parser = argparse.ArgumentParser()
inputs = parser.add_mutually_exclusive_group(required=True)
inputs.add_argument('--source', type=Path)
inputs.add_argument('--archive', type=Path)
args = parser.parse_args()
if args.archive:
    with tarfile.open(args.archive) as tar:
        source = tar.extractfile('target/sparc/int64_helper.c').read().decode()
else:
    source = args.source.read_text()
match = re.search(r'static bool do_modify_softint\(.*?\nvoid helper_write_softint\(.*?\n}', source, re.S)
assert match, 'Actual helper bodies not found'
helpers = match.group()
helpers, count = re.subn(r'(static bool do_modify_softint\([^)]*\)\s*\{)',
                         r'\1\n    inject_timer(env);', helpers, count=1)
assert count == 1
prefix = r'''
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#define CONF_MP_INTR 1
#define CPU_INTERRUPT_HARD 2
typedef struct { uint32_t softint; unsigned notifications; } CPUSPARCState;
static bool inject;
static void inject_timer(CPUSPARCState *env) {
    if (inject) { __atomic_fetch_or(&env->softint, 0x10000u, __ATOMIC_SEQ_CST); }
}
#define qatomic_fetch_or(p,v) __atomic_fetch_or(p,v,__ATOMIC_SEQ_CST)
#define qatomic_fetch_and(p,v) __atomic_fetch_and(p,v,__ATOMIC_SEQ_CST)
#define qatomic_xchg(p,v) __atomic_exchange_n(p,v,__ATOMIC_SEQ_CST)
#define qatomic_read(p) __atomic_load_n(p,__ATOMIC_SEQ_CST)
#define cpu_interrupts_enabled(e) true
#define env_cpu(e) (e)
#define cpu_set_interrupt(e,v) ((e)->notifications++)
#define trace_int_helper_set_softint(v) ((void)(v))
#define trace_int_helper_clear_softint(v) ((void)(v))
#define trace_int_helper_write_softint(v) ((void)(v))
'''
suffix = r'''
static int failures;
static void check(const char *name, uint32_t got, uint32_t want) {
    printf("%s %s got=0x%x want=0x%x\n", got == want ? "PASS" : "FAIL", name, got, want);
    failures += got != want;
}
int main(void) {
    CPUSPARCState e = {0};
    helper_set_softint(&e, 4); check("set", e.softint, 4);
    helper_set_softint(&e, 4); check("unchanged notification", e.notifications, 1);
    helper_clear_softint(&e, 4); check("clear", e.softint, 0);
    helper_write_softint(&e, 0x10008); check("write", e.softint, 0x10008);
    helper_clear_softint(&e, 8); check("clear preserves existing timer", e.softint, 0x10000);
    helper_clear_softint(&e, 0x10000); check("explicit timer ack", e.softint, 0);
    helper_set_softint(&e, 0x100000000ULL); check("64-bit argument truncation", e.softint, 0);
    inject = true;
    e.softint = 0; helper_set_softint(&e, 8);
    check("timer arriving during set", e.softint, 0x10008);
    e.softint = 8; helper_clear_softint(&e, 8);
    check("timer arriving during clear", e.softint, 0x10000);
    return failures ? 1 : 0;
}
'''
with tempfile.TemporaryDirectory(prefix='sparc-softint-test-') as tmp:
    c = Path(tmp) / 'test.c'
    exe = Path(tmp) / 'test'
    c.write_text(prefix + helpers + suffix)
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2', str(c), '-o', str(exe)], check=True)
    raise SystemExit(subprocess.run([str(exe)]).returncode)
