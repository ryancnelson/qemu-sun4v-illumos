import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { webcrypto } from 'node:crypto';
// Node 18 does not expose Web Crypto globally without an experimental flag.
// Use the real standard implementation for this browser-only API in host tests.
globalThis.crypto ??= webcrypto;
import { qemuArguments } from './config.mjs';
import { IMAGE_SIZE, IMAGE_SHA256, IMAGE_PATH, storageMode, storageArguments,
  selectedImage, validatedImage, loadImage } from './storage.mjs';

const image = new Uint8Array(await readFile(new URL('./assets/sentinel-32k.raw', import.meta.url)));
const response = (bytes, length = String(IMAGE_SIZE)) => new Response(bytes,
  { headers: length === null ? {} : { 'content-length': length } });

test('default and unrelated query do not fetch or attach media', async () => {
  const forbidden = () => { throw new Error('default must not fetch'); };
  for (const query of ['', '?inputDiagnostics=1']) {
    assert.equal(await selectedImage(query, forbidden), null);
    const args = [...qemuArguments(), ...storageArguments(storageMode(query))];
    assert.deepEqual(args, qemuArguments());
    assert.ok(!args.includes('-drive'));
  }
});
test('only one exact opt-in accepted; paths/argv/duplicates refused before fetch', async () => {
  for (const query of ['?storage=', '?storage=off', '?storage=/tmp/a',
    '?storage=sentinel&storage=sentinel', '?storage=sentinel%20-monitor%20stdio']) {
    let calls = 0;
    await assert.rejects(selectedImage(query, () => { calls++; }));
    assert.equal(calls, 0);
  }
});
test('fixed read-only ATAPI argv and MEMFS path', () => {
  assert.equal(IMAGE_PATH, '/sentinel.raw');
  assert.deepEqual(storageArguments(true), ['-drive',
    'file=/sentinel.raw,format=raw,if=ide,index=0,media=cdrom,readonly=on']);
  assert.throws(() => storageArguments('true'));
  assert.deepEqual(storageArguments(false), []);
});
test('frozen generated fixture accepted with exact size/hash', async () => {
  assert.equal(IMAGE_SIZE, 32768);
  assert.equal(IMAGE_SHA256, '52fa9b2c6313c7c50f430ea508815b0c1ed2bf7a5978ffb2131c21acffa5bdf5');
  assert.equal(await validatedImage(image), image);
  assert.deepEqual(await selectedImage('?storage=sentinel', async path => {
    assert.equal(path, './assets/sentinel-32k.raw'); return response(image);
  }), image);
});
test('wrong type, short/oversize and corrupt content refused', async () => {
  for (const bytes of [image.buffer, image.subarray(1), new Uint8Array(IMAGE_SIZE + 1)])
    await assert.rejects(validatedImage(bytes));
  const corrupt = image.slice(); corrupt[2048] ^= 1;
  await assert.rejects(validatedImage(corrupt), /hash mismatch/);
});
test('HTTP failure and missing/inexact length header refused before body read', async () => {
  await assert.rejects(loadImage(async () => new Response('', {status: 404})), /fetch failed/);
  for (const length of [null, '0', '32767', '32769', '032768'])
    await assert.rejects(loadImage(async () => response(image, length)), /length header/);
});
test('fragmented stream produces exact bytes', async () => {
  const chunks = [image.slice(0, 1), image.slice(1, 2049), image.slice(2049)];
  const stream = new ReadableStream({ pull(controller) {
    if (chunks.length) controller.enqueue(chunks.shift()); else controller.close();
  }});
  assert.deepEqual(await loadImage(async () => response(stream)), image);
});
test('lying length cannot permit overflow or truncation; reader is cancelled', async () => {
  for (const bytes of [image.subarray(1), new Uint8Array(IMAGE_SIZE + 1)]) {
    let cancelled = false, sent = false;
    const fake = {ok: true, headers: new Headers({'content-length': String(IMAGE_SIZE)}),
      body: {getReader: () => ({read: async () => sent ? {done: true} :
        (sent = true, {done: false, value: bytes}), cancel: async () => {cancelled = true;}})}};
    await assert.rejects(loadImage(async () => fake), /Truncated|exceeds bound/);
    assert.equal(cancelled, true);
  }
});
test('stream error propagates and cancels reader', async () => {
  let cancelled = false;
  await assert.rejects(loadImage(async () => ({ok: true,
    headers: new Headers({'content-length': String(IMAGE_SIZE)}),
    body: {getReader: () => ({read: async () => {throw new Error('read failed');},
      cancel: async () => {cancelled = true;}})}})), /read failed/);
  assert.equal(cancelled, true);
});
