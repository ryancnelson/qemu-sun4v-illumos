import json
from pathlib import Path
p=Path(__file__).parent/"candidate-v3"
items=[json.loads(l) for l in (p/"capture.log").read_text().splitlines() if l.startswith("{")]
st={x["label"]:x["registers"] for x in items if "registers" in x}
def r(label,n): return int(st[label][str(n)],16)
ptr=r("entry",8); count=r("entry",9)
raw=bytes.fromhex(next(x["raw"] for x in items if x.get("memory")==hex(ptr)))
avail=[tuple(int.from_bytes(raw[i+j:i+j+8],"big") for j in [0,8]) for i in range(0,len(raw),16)]
assert len(avail)==count
print("AVAILABLE count",count)
for a,s in avail: print(hex(a),hex(s),"end",hex(a+s))
pages=0
for i,((a,s),(n,t)) in enumerate(zip(avail,avail[1:])):
 assert r("pair-%d"%i,13)==a and r("pair-%d"%i,12)==s
 assert r("gap-%d"%i,13)==a+s and r("gap-%d"%i,12)==n
 assert n>=a+s
 pages+=(n-a-s+8191)//8192
assert pages==r("estimate-return",8)
pages_with_self=pages+(r("pool-request",27)*88+8191)//8192
nh=0; iterations=[]
while pages_with_self>1:
 k=(pages_with_self+7)//8; nh+=k; iterations.append(k); pages_with_self=(k*312+8191)//8192
nh+=2+count
size=((nh*312+r("pool-request",27)*88+8191)//8192)*8192
assert nh==r("pool-request",26) and size==r("pool-request",25)
print("ESTIMATOR",pages,"POOL_REQUEST",nh,"BYTES",size,"ARITHMETIC_CAPACITY",(size-r("pool-request",27)*88)//312,"iterations",iterations)
tp=r("translations-args",8); tn=r("translations-args",9)
trans=[]
for x in items:
 if "memory" in x and tp<=int(x["memory"],16)<tp+tn*24 and x["size"]==24:
  b=bytes.fromhex(x["raw"]); trans.append(tuple(int.from_bytes(b[j:j+8],"big") for j in [0,8,16]))
assert len(trans)==tn
print("TRANSLATIONS",tn)

current=[(int(x["address"],16),int(x["size"],16)) for x in items if x.get("label")=="checker-virt-avail-node"]
assert any(x.get("label")=="checker-virt-avail-complete" for x in items)
print("CONTEMPORANEOUS_AVAILABLE",len(current))
for a,z in current: print(hex(a),hex(z),"end",hex(a+z))
for entries in [avail,current]:
 for i,(a,z) in enumerate(entries):
  assert z>0 and a+z<=0x80000000000
  if i: assert entries[i-1][0]+entries[i-1][1]<=a
 assert all(max(a,0xfffce000)>=min(a+z,0xfffd6000) for a,z in entries)
checked=0
for a,z,tte in trans:
 if a<0x1000000: continue
 checked+=1
 overlaps=[(max(a,v),min(a+z,v+w)) for v,w in current if max(a,v)<min(a+z,v+w)]
 assert not overlaps,(hex(a),hex(z),overlaps)
print("SAME_TIME_CHECKED_TRANSLATIONS_DISJOINT",checked)
pools=[bytes.fromhex(x["raw"]) for x in items if x.get("memory")=="0x18207e8"]
assert len(pools)==2
for label,b in zip(["translations-entry","before-kmem64"],pools):
 used=int.from_bytes(b[24:32],"big");capacity=int.from_bytes(b[32:40],"big")
 assert capacity==(size-r("pool-request",27)*88)//312
 print("POOL",label,"used",used,"capacity",capacity)
assert r("before-kmem64",27)==0
base=int(next(x["raw"] for x in items if x.get("memory")=="0x18465f8"),16)
raw=bytes.fromhex(next(x["raw"] for x in items if x.get("memory")=="0x1839cf0"))
end=int.from_bytes(raw[8:16],"big")
assert end>=base
blocks=set()
for a,z,tte in trans:
 if a<0x1000000 or a in (0x1000000,0x1800000):continue
 blocks.update(range(a//65536,(a+z+65535)//65536))
assert len(blocks)==used
kmem_blocks=set(range(base//65536,(end+65535)//65536))
additional=len(kmem_blocks-blocks)
assert used+additional<=capacity
print("EFFECTIVE_PAGE_CODE",r("before-kmem64",27),"KMEM_BASE",hex(base),"KMEM_END",hex(end),"KMEM_SPAN_BLOCKS",len(kmem_blocks),"ADDITIONAL_BLOCKS",additional,"PREDICTED_POST_KMEM",used+additional,"MARGIN",capacity-used-additional)
assert "detach OK" in (p/"capture.log").read_text()
print("CAPTURE_REPLAY_PASS; post-kmem counter and usable physmem NOT CAPTURED")
