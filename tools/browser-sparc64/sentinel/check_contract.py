from pathlib import Path
import json, re, hashlib
d=Path(__file__).resolve().parent
raw=(d.parent/"assets/sentinel-32k.raw").read_bytes()
spec=json.loads((d/"expected.json").read_text())
assert hashlib.sha256(raw).hexdigest()==spec["image_sha256"]
lines=(d/"storage-control.fth").read_text().splitlines()
pos=0; actual=[]; opened=0; closed=[]
for line in lines:
    if 'open-dev' in line and not line.startswith(chr(92)):
        opened+=1; pos=0
    m=re.fullmatch(r'([0-9a-f]+) 0 " seek" s2h[12] \$call-method \.',line)
    if m: pos=int(m[1],16)
    if re.fullmatch(r's2buf 40 " read" s2h[12] \$call-method \.',line):
        actual.append(pos); pos+=64
    if re.fullmatch(r's2h[12] close-dev',line): closed.append(line.split()[0])
assert actual==[c["offset"] for c in spec["cases"]]==[0,256,2016,2080,2048,32704]
assert opened==2 and closed==["s2h1","s2h2"]
for c in spec["cases"]:
    assert bytes.fromhex(c["hex"])==raw[c["offset"]:c["offset"]+64]
assert max(actual)+64==len(raw)
assert sum(' read"' in line for line in lines)==6
assert sum('seek"' in line for line in lines)==5
assert sum('dump'==line.split()[-1] for line in lines if line and not line.startswith(chr(92)))==6
print("PASS: six command offsets/content, sequential cursor, two open/close lifetimes, five seeks, six dumps, EOF bound; static host contract only")
