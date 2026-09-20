"""Exercise the packaged proxy config with a private state directory."""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / 'appliances/sparc64-qemu-illumos-docker-guest/scripts/container-network.sh'


@unittest.skipUnless(shutil.which('tinyproxy') and os.geteuid() == 0,
                     'requires root and the appliance tinyproxy package')
class ProxyPrivateStateTest(unittest.TestCase):
    def test_connect_after_privilege_drop(self):
        template = SCRIPT.read_text().split('cat >"$proxy_config" <<EOF\n', 1)[1].split('\nEOF', 1)[0]
        with tempfile.TemporaryDirectory() as directory, socket.socket() as upstream:
            state = Path(directory)
            state.chmod(0o700)
            upstream.bind(('127.0.0.1', 0))
            upstream.listen()
            with socket.socket() as reserve:
                reserve.bind(('127.0.0.1', 0))
                port = reserve.getsockname()[1]
            config = template.replace('$LOG_DIR', directory).replace('$PROXY_PORT', str(port))
            config = config.replace('$HOST_IP', '127.0.0.1').replace('$GUEST_IP', '127.0.0.1')
            config = config.replace('ConnectPort 443', f'ConnectPort {upstream.getsockname()[1]}')
            path = state / 'tinyproxy.conf'
            path.write_text(config)
            with (state / 'proxy.log').open('wb') as output:
                process = subprocess.Popen(['tinyproxy', '-d', '-c', str(path)], stdout=output, stderr=output)
                try:
                    deadline = time.monotonic() + 10
                    response = b''
                    while time.monotonic() < deadline and process.poll() is None:
                        try:
                            with socket.create_connection(('127.0.0.1', port), timeout=1) as client:
                                client.sendall(f'CONNECT 127.0.0.1:{upstream.getsockname()[1]} HTTP/1.0\r\n\r\n'.encode())
                                response = client.recv(4096)
                                break
                        except (OSError, TimeoutError):
                            time.sleep(0.1)
                    self.assertIn(b'200 Connection established', response, (state / 'proxy.log').read_text())
                    self.assertIn('Now running as user "nobody"', (state / 'proxy.log').read_text())
                finally:
                    process.terminate()
                    process.wait(timeout=10)


if __name__ == '__main__':
    unittest.main()
