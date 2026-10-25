#!/usr/bin/env python3
"""Compile the actual source emitter, then validate and execute its Wasm."""
import pathlib, subprocess, sys, tempfile
source = pathlib.Path(sys.argv[1]).read_text()
start = source.index('static void tcg_wasm_out_sub2(')
end = source.index('\n}', start) + 2
function = source[start:end]
helpers = '''
#include <stdio.h>
typedef int TCGContext;
typedef int TCGReg;
#define TMP64_0_IDX 0
static void emit(int x) { printf("%02x", x); }
static void tcg_wasm_out_op_global_get_r(TCGContext*s,int r){emit(0x23);emit(r);}
static void tcg_wasm_out_op_global_set_r(TCGContext*s,int r){emit(0x24);emit(r);}
static void tcg_wasm_out_op_local_set(TCGContext*s,int r){emit(0x21);emit(r);}
static void tcg_wasm_out_op_local_get(TCGContext*s,int r){emit(0x20);emit(r);}
static void tcg_wasm_out_op_i64_sub(TCGContext*s){emit(0x7d);}
static void tcg_wasm_out_op_i64_gt_u(TCGContext*s){emit(0x56);}
static void tcg_wasm_out_op_i64_extend_i32_s(TCGContext*s){emit(0xac);}
static void tcg_wasm_out_op_i64_extend_i32_u(TCGContext*s){emit(0xad);}
'''
main = '''
int main(void) {
  /* disjoint, retl aliases al, retl aliases bl, all low aliases */
  tcg_wasm_out_sub2(0,4,5,0,1,2,3); puts("");
  tcg_wasm_out_sub2(0,0,1,0,1,2,3); puts("");
  tcg_wasm_out_sub2(0,2,3,0,1,2,3); puts("");
  tcg_wasm_out_sub2(0,0,1,0,1,0,3); puts("");
}
'''
with tempfile.TemporaryDirectory(prefix='wasm-sub2-') as tmp:
    c = pathlib.Path(tmp)/'emit.c'
    c.write_text(helpers + function + main)
    exe = pathlib.Path(tmp)/'emit'
    subprocess.run(['cc', str(c), '-o', str(exe)], check=True)
    bodies = subprocess.check_output([str(exe)], text=True).splitlines()
    subprocess.run(['node', sys.argv[2], *bodies], check=True)
