import test from 'node:test';
import assert from 'node:assert/strict';
import { qemuArguments, FIRMWARE_SHA256 } from './config.mjs';
test('single CPU firmware-only launch has explicit serial and disabled autoboot', () => {
  const args = qemuArguments();
  const value = flag => args[args.indexOf(flag) + 1];
  assert.equal(value('-M'), 'sun4u');
  assert.equal(value('-m'), '512');
  assert.equal(value('-smp'), '1');
  assert.equal(value('-monitor'), 'none');
  assert.equal(value('-serial'), 'stdio');
  assert.equal(value('-nic'), 'none');
  // This fork initializes Wasm translator TLS only in mttcg_cpu_thread_fn.
  assert.ok(args.includes('tcg,tb-size=64,thread=multi'));
  assert.ok(args.includes('auto-boot?=false'));
  assert.ok(!args.includes('-cdrom') && !args.includes('-drive'));
  assert.equal(FIRMWARE_SHA256.length, 64);
});
test('RAM control accepts supported sizes, rejects arbitrary arguments', () => {
  for (const size of [128, 256, 512, 1024, 1536]) {
    const args = qemuArguments(size);
    assert.equal(args[args.indexOf('-m') + 1], String(size));
  }
  assert.throws(() => qemuArguments('512 -monitor stdio'));
  assert.throws(() => qemuArguments(4096));
});
