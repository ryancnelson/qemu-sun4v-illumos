"""Offline real-source/raw-token regression, not SPARC trap emulation.

Interpret only the actual xlsplit body with explicit arithmetic primitives.
Refuse memory words: value-only contract must not perform memory accesses.
"""
import hashlib
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = Path(sys.argv.pop(1)).read_text()
EXPECTED = ['bxjoin','<l@','lxjoin','wxjoin','x,','x@','x!','/x','/x*',
            'xa+','xa1+','xbflip','xbflips','xbsplit','xlflip','xlflips',
            'xlsplit','xwflip','xwflips','xwsplit']

def dispatch(bits):
    branch = SOURCE.split("['], left-parse-string",1)[1].split('64bit? [IF]',1)[1]
    yes, no = branch.split('[ELSE]',1)
    text = yes if bits == 64 else no.split('[THEN]',1)[0]
    entries = []
    for line in text.splitlines():
        line = line.split('\\',1)[0].strip()
        match = re.fullmatch(r"([0-9a-f]+) n\['], (\S+)", line)
        if match:
            entries += [match[2]] * int(match[1],16)
        else:
            match = re.fullmatch(r"\['], (\S+)",line)
            if match: entries.append(match[1])
    return dict(enumerate(entries, 0x241))

LIB = (ROOT/'64bit.fs').read_text()
body = re.search(r': xlsplit\s+\([^)]*\)(.*?)\n;',LIB,re.S).group(1).split()
MASK = (1 << 64)-1

def execute(words, stack, returns):
    for word in words:
        if word == 'dup': stack.append(stack[-1])
        elif word == '>r': returns.append(stack.pop())
        elif word == 'r>': stack.append(returns.pop())
        elif word == 'swap': stack[-2:] = stack[-2:][::-1]
        elif word == 'and': stack.append(stack.pop() & stack.pop())
        elif word == 'rshift':
            n=stack.pop(); stack.append((stack.pop() & MASK) >> n)
        elif word == '0=': stack.append(MASK if stack.pop() == 0 else 0)
        elif word == 'xlsplit': execute(body,stack,returns)
        elif word in ('h#','d#'): pass
        elif word == 'ffffffff': stack.append(0xffffffff)
        elif word == '32': stack.append(32) # preceded by d# in exact body
        else: raise AssertionError('value contract reached forbidden word: '+word)

class Contract(unittest.TestCase):
    def test_all_shifted_slots(self):
        self.assertEqual(dispatch(64),dict(enumerate(EXPECTED,0x241)))
    def test_non64_slots(self):
        expected = {i:'reserved-fcode' for i in range(0x241,0x255)}
        expected[0x248]='/x'
        self.assertEqual(dispatch(32),expected)
    def test_actual_payload_x0_definition(self):
        raw=(ROOT/'zfs-payload.fcode').read_bytes()
        self.assertEqual(hashlib.sha256(raw).hexdigest(),
                         'f165c875826737037ee54940898081b9dd8fb43a4ff86a403fdc0e89f5e6fc7d')
        self.assertEqual(raw[1204:1212],bytes.fromhex('b60378303d082db7'))
        self.assertEqual(raw[1212:1219],bytes.fromhex('025134493423c2'))
        # Actual token bytes select the dispatch entry; do not hardcode xlsplit.
        names = [dispatch(64)[int.from_bytes(raw[1212:1214],'big')],
                 '0=', 'swap', '0=', 'and']
        for value in (0,1,0xffffffff,1<<32,0x100000001,1<<63,MASK):
            with self.subTest(value=value):
                stack=[0x123456789abcdef0,value]; returns=[]
                execute(names,stack,returns)
                self.assertEqual(stack,[0x123456789abcdef0,MASK if value==0 else 0])
                self.assertEqual(returns,[])
    def test_xlsplit_exact_source_values(self):
        for value in (0,1,0xffffffff,1<<32,0xfedcba9876543210,MASK):
            stack=[value]; returns=[]
            execute(body,stack,returns)
            self.assertEqual(stack,[value&0xffffffff,value>>32])
            self.assertEqual(returns,[])

unittest.main()
