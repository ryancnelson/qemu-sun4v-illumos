import json,hashlib
from pathlib import Path
p=Path('/tmp/macapp-sun4u-001-trellis-evidence/candidate-v3')
raw=(p/'capture.log').read_text(); data=[json.loads(s) for s in raw.splitlines() if s.startswith('{')]
regs={x['label']:x['registers'] for x in data if 'registers' in x}
def r(l,n):return int(regs[l][str(n)],16)
def chunks(b,n):return [tuple(int.from_bytes(b[j:j+8],'big') for j in range(i,i+n,8)) for i in range(0,len(b),n)]
def mem(addr):return [bytes.fromhex(x['raw']) for x in data if x.get('memory')==hex(addr)]
avail=chunks(mem(r('entry',8))[0],16); assert len(avail)==r('entry',9)==23
assert r('entry',64)==0x10136a0 and r('translations',64)==0x1016bd0 and r('before-kmem64',64)==0x1016f20
head=int.from_bytes(mem(0x1846620)[0],'big'); ptr=head; prev=0; nodes=[];seen=set()
while ptr:
    assert ptr not in seen;seen.add(ptr)
    b=mem(ptr)[0]; assert len(b)==32
    a,z,n,back=chunks(b,32)[0];assert back==prev and z>0
    nodes.append((a,z));prev,ptr=ptr,n
assert len(nodes)==22
tp,tn=r('translations-args',8),r('translations-args',9)
tr=[chunks(mem(tp+24*i)[0],24)[0] for i in range(tn)]
assert len(tr)==166
for entries in (avail,nodes):
    for i,(a,z) in enumerate(entries):
        assert a%8192==z%8192==0 and a+z<=0x80000000000
        assert i==0 or entries[i-1][0]+entries[i-1][1]<=a
        assert max(a,0xfffce000)>=min(a+z,0xfffd6000)
checked=[t for t in tr if t[0]>=0x1000000]
assert len(checked)==165
# Stronger than exact B134 full-containment check, including every remaining-page suffix.
assert all(max(a,v)>=min(a+z,v+w) for a,z,t in checked for v,w in nodes)
for a in (0xfffce000,0xfffd0000):
    t=next(t for t in tr if t[0]==a);print('MMIO',*[hex(x) for x in t])
pages=0
for i,((a,z),(v,w)) in enumerate(zip(avail,avail[1:])):
    assert (a,z)==(r('pair-'+str(i),13),r('pair-'+str(i),12))
    assert (a+z,v)==(r('gap-'+str(i),13),r('gap-'+str(i),12))
    assert v>=a+z
    pages+=(v-a-z+8191)//8192
assert pages==r('estimate-return',8)==27601
nh1=r('pool-request',27); work=pages+(nh1*88+8191)//8192;nh8=0
while work>1:
    blocks=(work+7)//8;nh8+=blocks;work=(blocks*312+8191)//8192
nh8+=len(avail)+2
size=((nh8*312+nh1*88+8191)//8192)*8192;cap=(size-nh1*88)//312
assert (nh8,size)==(r('pool-request',26),r('pool-request',25))==(3493,0x10e000)
pool=mem(0x18207e8); assert len(pool)==2
counts=[chunks(b,48)[0][3:5] for b in pool]; assert counts==[(0,3500),(3085,3500)]
assert r('before-kmem64',27)==0
base=int.from_bytes(mem(0x18465f8)[0],'big');end=int.from_bytes(mem(0x1839cf0)[0][8:16],'big')
mapped=set()
for a,z,t in checked:
    if a not in (0x1000000,0x1800000):mapped.update(range(a//65536,(a+z+65535)//65536))
assert len(mapped)==3085
km=set(range(base//65536,(end+65535)//65536));assert len(km-mapped)==149
assert 'detach OK' in raw
c=(p/'console.log').read_text();h=(p/'harness.log').read_text()
assert 'SUN4U_OPENBIOS_BOOT=PASS' in h and 'User selected: English' in c and 'Configuring devices.' in c
assert 'panic' not in c.lower() and 'Requesting System Maintenance Mode' not in c
assert (p/'harness-exit-status.txt').read_text().strip()=='0'
assert (p/'capture-exit-status.txt').read_text().strip()=='0'
inspect=json.loads((p/'container-started.json').read_text())[0]
print('RESOURCE',inspect['HostConfig']['Memory'],inspect['HostConfig']['NanoCpus'],'CMD',inspect['Config']['Cmd'])
assert inspect['HostConfig']['Memory']==2147483648 and inspect['HostConfig']['NanoCpus']==1000000000
print('PASS raw-chain',hex(head),len(nodes),'checked',len(checked),'pages',pages,'nhblk1',nh1,'request',nh8,'bytes',hex(size),'capacity',cap,'observed-pre',counts[-1][0],'predicted-post',3085+149,'predicted-margin',cap-3085-149)
print('KMEM',hex(base),hex(end),'high-records',sum(a>=0x30000000000 for a,z,t in tr))
for f in ['capture.log','console.log','harness.log']: print('SHA256',f,hashlib.sha256((p/f).read_bytes()).hexdigest())
