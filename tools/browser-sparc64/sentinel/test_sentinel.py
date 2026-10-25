#!/usr/bin/env python3
import hashlib,json,pathlib,subprocess,sys,tempfile,unittest
import sentinel as s
HERE=pathlib.Path(__file__).resolve().parent
class Sentinel(unittest.TestCase):
 def test_deterministic_unique_sectors_and_windows(self):
  data=s.image();self.assertEqual(len(data),32768);self.assertEqual(data,s.image())
  self.assertEqual(len({data[i:i+2048] for i in range(0,len(data),2048)}),16)
  self.assertEqual(len({data[i:i+64] for i in range(len(data)-63)}),len(data)-63)
 def test_actual_artifact(self):
  self.assertEqual((HERE.parent/'assets/sentinel-32k.raw').read_bytes(),s.image())
  self.assertEqual(json.loads((HERE/'manifest.json').read_text())['sha256'],hashlib.sha256(s.image()).hexdigest())
 def test_explicit_offsets_and_cross_sector(self):
  for o in s.OFFSETS+(0x7f1,):
   with self.subTest(offset=o):self.assertTrue(s.verify(s.image()[o:o+64],o,64)['verified'])
 def test_old_repeating_pattern_gap(self):
  old=bytes(range(256))*128
  self.assertEqual(old[:64],old[0x100:0x140])
  self.assertNotEqual(s.image()[:64],s.image()[0x100:0x140])
  with self.assertRaises(ValueError):s.verify(s.image()[:64],0x100,64)
 def test_wrong_sector_alias(self):
  for o in (0x800,0x1800,0x7800):
   with self.subTest(offset=o),self.assertRaises(ValueError):s.verify(s.image()[:64],o,64)
 def test_truncation_extra_and_bit_flip(self):
  data=s.expected(0x800,64)
  for bad in (data[:-1],data+b'x',bytes([data[0]^1])+data[1:]):
   with self.subTest(size=len(bad)),self.assertRaises(ValueError):s.verify(bad,0x800,64)
 def test_invalid_bounds(self):
  for o,n in ((-1,64),(0,0),(0,63),(0,4097),(32768,64),(32705,64),(1<<64,64)):
   with self.subTest(offset=o,length=n),self.assertRaises(ValueError):s.expected(o,n)
 def test_cli_failure_and_no_overwrite(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'data';p.write_bytes(s.expected(0,64))
   base=[sys.executable,str(HERE/'sentinel.py')]
   good=subprocess.run(base+['verify',str(p),'--offset','0','--length','64'],capture_output=True)
   self.assertEqual(good.returncode,0)
   bad=subprocess.run(base+['verify',str(p),'--offset','0x800','--length','64'],capture_output=True)
   self.assertEqual(bad.returncode,1);self.assertEqual(bad.stdout,b'')
   before=p.read_bytes()
   refuse=subprocess.run(base+['generate',str(p)],capture_output=True)
   self.assertEqual(refuse.returncode,1);self.assertEqual(p.read_bytes(),before)
if __name__=='__main__':unittest.main(verbosity=2)
