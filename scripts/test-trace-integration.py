#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE=Path(__file__).parent
class Integration(unittest.TestCase):
    def run_shell(self,body,flag="1"):
        with tempfile.TemporaryDirectory(prefix="trace ' quoted $ space ") as d:
            env=dict(os.environ,TEST_ROOT=d,TEST_SRC=str(HERE),SUN4U_TRACE_CMD646=flag)
            result=subprocess.run(["bash","-c",body],env=env,text=True,capture_output=True)
            files={p.name:p.read_text() for p in Path(d).iterdir() if p.is_file()}
            return result,files
    prelude='''set -eu
run_dir=$TEST_ROOT
console_log="$run_dir/console.log"
container=unused
keep_guest=0; keep_maintenance=0; preserve_ready=0
source "$TEST_SRC/console-outcomes.sh"
source "$TEST_SRC/cmd646-trace.sh"
cleanup() { :; }
'''
    def test_off_no_args_no_files(self):
        r,f=self.run_shell(self.prelude+'''prepare_trace
[[ ${#trace_qemu_args[@]} == 0 ]]
''',"0")
        self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(f,{})
    def test_quoted_paths_exact_args(self):
        r,f=self.run_shell(self.prelude+'''prepare_trace
printf '%s\n' "${trace_qemu_args[@]}"
''')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(r.stdout.splitlines(),["-trace","events=/run/sun4u/cmd646.events","-msg","timestamp=on","-D","/run/sun4u/cmd646.trace"])
        self.assertEqual(len(f["cmd646.events"].splitlines()),7)
    def test_invalid_trace_overrides_pass(self):
        r,f=self.run_shell(self.prelude+'''printf 'bad backend\n' >"$run_dir/cmd646.trace"
printf 'console retained\n' >"$console_log"
finalize_run 0
''')
        self.assertEqual(r.returncode,27,r.stderr)
        self.assertIn("SUN4U_OUTCOME=TRACE_INCOMPLETE",f["outcome.env"])
        self.assertIn("console retained",f["console-final.log"])
    def test_signal_retains_cancellation(self):
        r,f=self.run_shell(self.prelude+'''trap 'finalize_run $?' EXIT
trap 'cancel_run 143' TERM
printf 'raw before cancellation\n' >"$run_dir/cmd646.trace"
kill -TERM $$
''')
        self.assertEqual(r.returncode,143,r.stderr)
        self.assertIn("CANCELLED",f["outcome.env"])
        self.assertIn("raw before",f["cmd646.trace"])
    def test_maintenance_stays_nonpass(self):
        r,f=self.run_shell(self.prelude+'''capture_outcome MAINTENANCE 21
finalize_run 21
''')
        self.assertEqual(r.returncode,21,r.stderr)
        self.assertIn("MAINTENANCE",f["outcome.env"])
        self.assertIn("trace-incomplete.json",f)
    def test_preservation_incompatible_only_when_on(self):
        body='keep_guest=0; keep_maintenance=1; source "$TEST_SRC/cmd646-trace.sh"'
        r,_=self.run_shell(body);self.assertEqual(r.returncode,2)
        r,_=self.run_shell(body,"0");self.assertEqual(r.returncode,0)
    def test_watcher_exit_without_marker_overrides_pass(self):
        r,f=self.run_shell(self.prelude+'''printf '8@1.0:pci_cfg_read cmd646-ide 01:03.0 @0x50 -> 0x0\\n' >"$run_dir/cmd646.trace"
printf 'pci_cfg_read\\n' >"$run_dir/cmd646.events"
(exit 1) &
trace_watch_pid=$!
# Simulate the watcher dying immediately after a successful liveness check.
check_trace() { return 0; }
finalize_run 0
''')
        self.assertEqual(r.returncode,27,r.stderr)
        self.assertIn("TRACE_INCOMPLETE",f["outcome.env"])

if __name__=="__main__":unittest.main()
