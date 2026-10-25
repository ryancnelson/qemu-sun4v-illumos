import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { observeBacking } from './backing-observation.mjs';
import { IMAGE_SIZE, IMAGE_SHA256, validatedImage, selectedImage } from './input.mjs';
globalThis.crypto ??= webcrypto;
const source = new Uint8Array(await readFile(new URL('../../assets/sentinel-32k.raw', import.meta.url)));
function fileMock(bytes, fail = false) {
  const calls = [];
  const FS = {
    stat(path) { calls.push(['stat', path]); return {size: bytes.length}; },
    open(path, mode) { calls.push(['open', path, mode]); return 7; },
    read(fd, buffer, offset, length, position) {
      calls.push(['read', fd, offset, length, position]);
      if (fail) throw new Error('read failed');
      const n = Math.min(bytes.length, length); buffer.set(bytes.subarray(0, n)); return n;
    },
    close(fd) { calls.push(['close', fd]); },
  };
  return {FS, calls};
}
test('actual backing read has fixed path/mode/position/bound and closes', async () => {
  const {FS, calls} = fileMock(source.slice());
  const result = await observeBacking(FS);
  assert.equal(result.sha256, IMAGE_SHA256); assert.equal(result.matchesPinnedInput, true);
  assert.deepEqual(calls, [['stat','/sentinel.raw'], ['open','/sentinel.raw','r'],
    ['read',7,0,IMAGE_SIZE+1,0], ['close',7]]);
});
test('backing mutation detected despite unchanged original input buffer', async () => {
  const backing = source.slice(); const {FS} = fileMock(backing);
  assert.equal((await observeBacking(FS)).matchesPinnedInput, true);
  backing[2048] ^= 1;
  assert.equal((await observeBacking(FS)).matchesPinnedInput, false);
  assert.equal(await validatedImage(source), source);
});
test('short or oversize actual file refused; fixed read bound maintained', async () => {
  for (const bytes of [source.subarray(1), new Uint8Array(IMAGE_SIZE+100)]) {
    const {FS,calls} = fileMock(bytes); await assert.rejects(observeBacking(FS), /size changed/);
    assert.deepEqual(calls.at(-1), ['close',7]);
  }
});
test('read failure still closes stream', async () => {
  const {FS,calls} = fileMock(source,true);
  await assert.rejects(observeBacking(FS), /read failed/);
  assert.deepEqual(calls.at(-1), ['close',7]);
});
test('default input selection performs no media fetch', async () => {
  assert.equal(await selectedImage('', () => {throw new Error('unexpected fetch');}), null);
});
