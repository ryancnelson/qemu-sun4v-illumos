'use strict';
const assert = require('assert');
const leb = n => { const r=[]; do {let b=n&127;n>>>=7;r.push(b|(n?128:0));}while(n); return r; };
const section=(id, a)=>[id,...leb(a.length),...a];
const str=s=>[...leb(s.length),...Buffer.from(s)];
function moduleBytes(hex) {
  const code=[1,1,0x7e,...Buffer.from(hex,'hex'),0x0b]; // one i64 local
  const globals=[6,...Array.from({length:6},()=>[0x7e,1,0x42,0,0x0b]).flat()];
  const exports=[7,...str('run'),0,0,...Array.from({length:6},(_,i)=>[...str('g'+i),3,i]).flat()];
  return Uint8Array.from([0,97,115,109,1,0,0,0,
    ...section(1,[1,0x60,0,0]),...section(3,[1,0]),...section(6,globals),
    ...section(7,exports),...section(10,[1,...leb(code.length),...code])]);
}
const u=x=>BigInt.asUintN(64,x), mask=(1n<<64n)-1n;
const cases=[[5n,7n,3n,2n],[0n,1n,1n,0n],[mask,mask,mask,mask],
 [0n,0n,mask,mask],[mask,0n,1n,mask],[0x8000000000000000n,7n,mask,5n]];
let count=0;
for (const [alias,hex] of process.argv.slice(2).entries()) {
  const bytes=moduleBytes(hex);
  assert(WebAssembly.validate(bytes),`alias${alias}: emitted module must validate`);
  const e=new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
  for (const vals of cases) {
    const [al,ah,bl,bh]=vals; const b=alias===3?al:bl;
    [al,ah,bl,bh,0n,0n].forEach((v,i)=>e['g'+i].value=v);
    const expected=BigInt.asUintN(128,((ah<<64n)|al)-((bh<<64n)|b));
    e.run(); const r=alias===0?[4,5]:alias===2?[2,3]:[0,1];
    assert.equal(u(e['g'+r[0]].value),expected&mask,`alias${alias} low`);
    assert.equal(u(e['g'+r[1]].value),expected>>64n,`alias${alias} high`);
    count++;
  }
}
console.log(`PASS: source-emitted sub2 Wasm validation and ${count} arithmetic/alias cases`);
