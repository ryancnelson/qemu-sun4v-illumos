import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { webcrypto } from 'node:crypto';
import { overlayArguments } from './overlay-config.mjs';
import { qemuArguments } from '../../config.mjs';
import { captureIdentity, backingLinkage } from './linkage.mjs';
import { prepareBacking } from './prepare-backing.mjs';
import { selectedImage, storageMode } from './input.mjs';
globalThis.crypto ??= webcrypto;
const image = new Uint8Array(await readFile(new URL('../../assets/sentinel-32k.raw', import.meta.url)));
function mock() {
  let bytes = image.slice();
  const node = {id: 42}, events = [];
  const FS = { streams: [], node,
    lookupPath: () => ({node: FS.node}),
    mkdirTree: path => events.push(['mkdir',path]),
    isDir: mode => mode === 1,
    stat: path => path === '/var/tmp' ? {mode: 1} : {size: bytes.length},
    writeFile: (path,data) => {events.push(['write',path]); bytes=data.slice();},
    open: () => 7, close: () => {},
    read: (fd,buffer,offset,length) => { const n=Math.min(bytes.length,length); buffer.set(bytes.subarray(0,n)); return n; },
  };
  const mod = {FS, addRunDependency: x => events.push(['add',x]),
    removeRunDependency: x => events.push(['remove',x])};
  return {FS,node,mod,events};
}
test('default exact argv unchanged; fixed opt-in matches Flint contract', async () => {
  const config = JSON.parse(await readFile(new URL('./fixed-config.json', import.meta.url)));
  assert.deepEqual([...qemuArguments(512), ...overlayArguments(true,512)], config.argv);
  assert.deepEqual([...qemuArguments(), ...overlayArguments(false,512)], qemuArguments());
  assert.throws(() => overlayArguments(true,256));
  assert.throws(() => overlayArguments('true',512));
  assert.equal(await selectedImage('', () => {throw Error('unexpected fetch');}),null);
  assert.equal(storageMode('?storage=snapshot-sentinel'),true);
  assert.throws(() => storageMode('?storage=sentinel'));
  assert.throws(() => storageMode('?storage=snapshot-sentinel&storage=snapshot-sentinel'));
});
test('hold main until actual backing hash and identity recorded', async () => {
  const {mod,events,node} = mock(); let recorded = false;
  await prepareBacking(mod,image,(identity,observed) => {
    assert.equal(identity.node,node); assert.equal(observed.matchesPinnedInput,true);
    assert.ok(!events.some(x=>x[0]==='remove')); recorded=true;
  });
  assert.equal(recorded,true);
  assert.deepEqual(events,[['add','backing-before'],['mkdir','/var/tmp'],['write','/sentinel.raw'],['remove','backing-before']]);
});
test('relocated fixed asset uses committed validator and exact fixture', async () => {
  let calls=0;
  const loaded=await selectedImage('?storage=snapshot-sentinel',async url=>{
    calls++;
    assert.equal(url,new URL('../../assets/sentinel-32k.raw',import.meta.url).href);
    return new Response(image,{headers:{'content-length':'32768'}});
  });
  assert.equal(calls,1);assert.deepEqual(loaded,image);
  await assert.rejects(selectedImage('?storage=snapshot-sentinel',async()=>
    new Response(new Uint8Array(32768),{headers:{'content-length':'32768'}})),/hash mismatch/);
});
test('failed temp setup or actual backing hash keeps launch held', async () => {
  for (const failure of ['directory','hash']) {
    const {mod,events} = mock();
    if (failure==='directory') mod.FS.isDir=()=>false;
    else { const write=mod.FS.writeFile; mod.FS.writeFile=(path,data)=>{const changed=data.slice();changed[0]^=1;write(path,changed);}; }
    await assert.rejects(prepareBacking(mod,image,()=>{throw Error('must not record pass');}));
    assert.ok(!events.some(x=>x[0]==='remove'));
  }
});
test('same main FS/node plus read-only base stream required', () => {
  const {FS,node} = mock(); const identity=captureIdentity(FS);
  assert.throws(()=>backingLinkage(FS,identity),/No consistent/);
  FS.streams=[{fd:3,path:'/sentinel.raw',node,flags:0,isWrite:false},
    {fd:4,path:'/var/tmp/vl.ABC123',node:{id:43},flags:2,isWrite:true}];
  const result=backingLinkage(FS,identity);
  assert.equal(result.sameBackingNode,true); assert.equal(result.temporaryStreams.length,1);
  assert.throws(()=>backingLinkage({...FS},identity),/instance changed/);
  FS.streams[0].isWrite=true;assert.throws(()=>backingLinkage(FS,identity),/No consistent/);
  FS.streams[0].isWrite=false;FS.node={id:42};assert.throws(()=>backingLinkage(FS,identity),/node replaced/);
});
test('replaced stream node and oversized stream metadata refused', () => {
  const {FS,node}=mock();const identity=captureIdentity(FS);
  FS.streams=[{fd:3,path:'/sentinel.raw',node:{id:42},isWrite:false}];
  assert.throws(()=>backingLinkage(FS,identity),/No consistent/);
  FS.streams=Array(129);assert.throws(()=>backingLinkage(FS,identity),/bound/);
});
