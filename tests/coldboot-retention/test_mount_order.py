import copy, hashlib, importlib.util, json, os
from pathlib import Path
import tempfile, unittest
from unittest.mock import patch
from types import SimpleNamespace

P=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("subject",P.parents[1]/"scripts/retention.py")
r=importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
NATIVE=json.loads((P/"native-fixtures/mount-order-boot3.json").read_text())
assert [x["path"] for x in NATIVE["diff_after_existing_oom_normalization"]]==["/Mounts"]
DELTA=NATIVE["diff_after_existing_oom_normalization"][0]

def obj(mounts):
    # Other fields are explicit fixture constants; exact native mount arrays are unchanged.
    return {"Id":NATIVE["cid"],"Image":"pinned-image", "Config":{"Labels":{"owner":NATIVE["owner"]}},
            "HostConfig":{"OomKillDisable":False,"Memory":2147483648},"Mounts":copy.deepcopy(mounts)}

class Tests(unittest.TestCase):
    def test_exact_native_reorder_equal(self):
        a=obj(DELTA["before"]); b=obj(DELTA["actual"])
        self.assertNotEqual(a["Mounts"],b["Mounts"])
        self.assertEqual(r.fingerprint(a),r.fingerprint(b))

    def test_every_native_mount_field_still_enforced(self):
        original=obj(DELTA["before"])
        for field,value in (("Type","volume"),("Source","/different-disk"),("Destination","/different"),
                            ("Mode","ro"),("RW",True),("Propagation","rshared")):
            with self.subTest(field=field):
                changed=obj(DELTA["actual"])
                changed["Mounts"][0][field]=value
                self.assertNotEqual(r.fingerprint(original),r.fingerprint(changed))

    def test_missing_added_and_duplicate_mounts_refused(self):
        original=obj(DELTA["before"])
        missing=copy.deepcopy(original); missing["Mounts"].pop()
        self.assertNotEqual(r.fingerprint(original),r.fingerprint(missing))
        added=copy.deepcopy(original); extra=copy.deepcopy(added["Mounts"][0]); extra["Destination"]="/extra"
        added["Mounts"].append(extra)
        self.assertNotEqual(r.fingerprint(original),r.fingerprint(added))
        duplicate=copy.deepcopy(original); duplicate["Mounts"].append(copy.deepcopy(duplicate["Mounts"][0]))
        with self.assertRaisesRegex(ValueError,"duplicate"): r.fingerprint(duplicate)

    def test_no_other_identity_weakening_or_input_mutation(self):
        a=obj(DELTA["before"]); saved=copy.deepcopy(a)
        r.fingerprint(a); self.assertEqual(a,saved)
        for section,key,value in (("HostConfig","Memory",1),("HostConfig","OomKillDisable",True),("Config","Labels",{})):
            changed=copy.deepcopy(a); changed[section][key]=value
            self.assertNotEqual(r.fingerprint(a),r.fingerprint(changed))
        changed=copy.deepcopy(a); changed["Id"]="wrong"
        self.assertNotEqual(r.fingerprint(a),r.fingerprint(changed))

    def test_existing_unsorted_saved_record_reconciles_without_rewrite(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp); (p/"preflight.json").write_bytes(b"{}")
            old=obj(DELTA["before"]); actual=obj(DELTA["actual"])
            record={"cid":NATIVE["cid"],"owner":NATIVE["owner"],"transport":"qemu-unix-serial-v1",
                    "boot_id":"fixture-boot","preflight_sha256":hashlib.sha256(b"{}").hexdigest(),"fingerprint":old}
            encoded=json.dumps(record).encode(); (p/"retention.json").write_bytes(encoded)
            c=SimpleNamespace(owned=lambda e,t:(NATIVE["cid"],actual))
            original_read=Path.read_text
            def read(path,*args,**kw):
                if str(path)=="/proc/sys/kernel/random/boot_id": return "fixture-boot"
                return original_read(path,*args,**kw)
            with patch.object(Path,"read_text",read):
                self.assertEqual(r.inspect_retained(c,p,NATIVE["owner"])[0],NATIVE["cid"])
            self.assertEqual((p/"retention.json").read_bytes(),encoded)

    def test_malformed_destination_refused(self):
        for bad in (None,3,{},"relative"):
            changed=obj(DELTA["before"]); changed["Mounts"][0]["Destination"]=bad
            with self.assertRaises(ValueError): r.fingerprint(changed)

if __name__=="__main__": unittest.main()
