import json
import os
from pathlib import Path
import socket
import tempfile
import unittest
from unittest.mock import patch, Mock
import baseline
import coldboot_fresh as c
import fresh_serial as f
from boot_protocol import COMMANDS, FW, ROOT


class Wire:
    def __init__(self, tail=b''):
        self.responses = [b'Welcome to OpenBIOS v1.1\r\n0 > ']
        self.responses += [v[:-1] + b'  ok\r\n0 > ' for v in COMMANDS[:-1]]
        self.responses += [tail, b''] if tail else [b'']
        self.sent = []
        self.closed = False
    def settimeout(self, value): pass
    def connect(self, path): self.path = path
    def recv(self, count): return self.responses.pop(0)
    def sendall(self, data): self.sent.append(data)
    def close(self): self.closed = True


class Tests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir='/tmp')
        self.e = Path(self.tmp.name).resolve() / 'fresh'
        self.e.mkdir(mode=0o700)
        self.owner, self.cid = 'a' * 32, 'b' * 64
        self.lease = f.acquire(self.e, self.owner)
        self.listener = socket.socket(socket.AF_UNIX)
        self.listener.bind(str(self.e / 'serial.sock'))
    def tearDown(self):
        self.listener.close()
        self.lease.close()
        self.tmp.cleanup()
    def drive(self, wire):
        with patch.object(f, 'validate') as validate, patch.object(f.socket, 'socket', return_value=wire):
            result = f.drive(c, self.e, self.owner, self.cid, 2, self.lease)
        self.assertEqual(validate.call_count, 2)
        return result
    def test_default_argv_exactly_unchanged(self):
        for keep in (False, True):
            self.assertEqual(c.qemu_argv(keep), baseline.qemu_argv(keep))
            args = tuple(Path('/a b') for _ in range(4)) + ('owner', 'boot', 'identity', keep)
            self.assertEqual(c.create_argv(*args), baseline.create_argv(*args))
    def test_fresh_wait_only_serial(self):
        old = c.qemu_argv(True)
        new = c.qemu_argv(True, True)
        self.assertEqual(sum(a != b for a,b in zip(old,new)), 1)
        self.assertIn('wait=on,logfile=', new[new.index('-chardev')+1])
        self.assertIn('monitor.sock,server=on,wait=off', ' '.join(new))
        with self.assertRaises(ValueError): c.qemu_argv(False, True)
    def test_existing_lease_refused(self):
        with self.assertRaises(FileExistsError): f.acquire(self.e, self.owner)
    def test_nonprivate_evidence_refused(self):
        self.e.chmod(0o755)
        with self.assertRaises(ValueError): f.acquire(self.e, self.owner)
    def test_exact_sequence_and_login_is_only_prompt(self):
        wire = Wire(ROOT+b'\nopensolaris console login: ')
        result = self.drive(wire)
        self.assertEqual(wire.sent, list(COMMANDS))
        self.assertTrue(wire.closed)
        self.assertEqual(result['outcome'], 'LOGIN_PROMPT_OBSERVED')
        self.assertEqual(result['acceptance'], 'NOT_ESTABLISHED')
        self.assertFalse(result['authenticated_login'])
        self.assertEqual(result['observations'], ['ROOT_MOUNT', 'LOGIN'])
        self.assertIn('SEND_COMPLETED', (self.e/'driver.tx.jsonl').read_text())
    def test_eof_retains_and_records(self):
        result = self.drive(Wire())
        self.assertEqual(result['outcome'], 'EOF')
        self.assertEqual(result['cleanup'], 'NO_AUTOMATIC_STOP')
        self.assertTrue((self.e/'driver-outcome.json').exists())
    def test_cancel_retains_and_closes(self):
        wire = Wire()
        wire.recv = Mock(side_effect=KeyboardInterrupt())
        self.assertEqual(self.drive(wire)['outcome'], 'CANCELLED')
        self.assertTrue(wire.closed)
    def test_partial_send_error_records_intent_not_completion(self):
        wire = Wire()
        wire.sendall = Mock(side_effect=OSError('partial send possible'))
        self.assertEqual(self.drive(wire)['outcome'], 'DRIVER_ERROR_INCOMPLETE')
        tx=(self.e/'driver.tx.jsonl').read_text()
        self.assertIn('SEND_INTENT',tx)
        self.assertNotIn('SEND_COMPLETED',tx)
    def test_wrong_prompt_no_commands(self):
        wire = Wire(); wire.responses=[b'kernel prompt\n',b'']
        self.drive(wire)
        self.assertEqual(wire.sent,[])
    def test_panic_after_root_remains_panic(self):
        result=self.drive(Wire(ROOT+b'\npanic[cpu0]: test\n'))
        self.assertEqual(result['outcome'],'PANIC')
        self.assertEqual(result['observations'],['ROOT_MOUNT','PANIC'])
    def test_validate_failure_never_connects(self):
        with patch.object(f,'validate',side_effect=ValueError('CID mismatch')), patch.object(f.socket,'socket') as ctor:
            result=f.drive(c,self.e,self.owner,self.cid,2,self.lease)
        ctor.assert_not_called()
        self.assertEqual(result['outcome'],'DRIVER_ERROR_INCOMPLETE')
    def test_closed_lease_rejected_before_inspect(self):
        self.lease.close()
        with patch.object(f.retention,'inspect_retained') as inspect:
            with self.assertRaises(ValueError): f.validate(c,self.e,self.owner,self.cid,self.lease)
        inspect.assert_not_called()
    def test_bounded_idle_timeout_no_stop(self):
        wire=Wire(); wire.recv=Mock(side_effect=socket.timeout())
        with patch.object(f,'validate'), patch.object(f.socket,'socket',return_value=wire), patch.object(c,'stop_owned') as stop:
            result=f.drive(c,self.e,self.owner,self.cid,.01,self.lease)
        self.assertEqual(result['outcome'],'TIMEOUT')
        self.assertTrue(wire.closed)
        self.assertEqual(wire.sent,[])
        stop.assert_not_called()
    def test_output_creation_failure_no_connect_no_stop(self):
        (self.e/'driver.rx.raw').write_bytes(b'previous evidence')
        with patch.object(f.socket,'socket') as sock, patch.object(c,'stop_owned') as stop:
            result=f.drive(c,self.e,self.owner,self.cid,1,self.lease)
        self.assertEqual(result['outcome'],'DRIVER_ERROR_INCOMPLETE')
        sock.assert_not_called(); stop.assert_not_called()
        self.assertEqual((self.e/'driver.rx.raw').read_bytes(),b'previous evidence')
    def test_exact_native_identity_gate(self):
        config=dict(Cmd=['-c','socket,id=owner_serial,path=/run/sun4u/serial.sock,server=on,wait=on,logfile=/run/sun4u/serial.log,logappend=on'],
                    OpenStdin=False,StdinOnce=False,AttachStdin=False,Tty=False)
        obj={'State':{'Running':True},'Config':config,'Mounts':[
            {'Destination':'/firmware.bin','Source':'/firmware','Type':'bind','RW':False},
            {'Destination':'/run/sun4u','Source':str(self.e),'Type':'bind','RW':True}]}
        (self.e/'preflight.json').write_text(json.dumps({'firmware_sha256':FW}))
        with patch.object(f.retention,'inspect_retained',return_value=(self.cid,obj)), patch.object(c,'regular',return_value=Path('/firmware')), patch.object(c,'digest',return_value=FW):
            f.validate(c,self.e,self.owner,self.cid,self.lease)
            with self.assertRaises(ValueError): f.validate(c,self.e,self.owner,'c'*64,self.lease)
            obj['State']['Running']=False
            with self.assertRaises(ValueError): f.validate(c,self.e,self.owner,self.cid,self.lease)
            obj['State']['Running']=True
            config['Cmd']=['wait=off']
            with self.assertRaises(ValueError): f.validate(c,self.e,self.owner,self.cid,self.lease)
    def test_cli_contract_requires_retention_and_exclusive_console(self):
        args=['driver','--disk','/x','--firmware','/y','--qemu','/z','--evidence',str(self.e),
              '--offline-clean-shutdown-confirmed','--exclusive-host-confirmed','--serial-boot']
        with patch('sys.argv',args), self.assertRaises(SystemExit) as error:
            c.main()
        self.assertEqual(error.exception.code,2)


if __name__=='__main__': unittest.main()
