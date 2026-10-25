import threading
import unittest
import urllib.request
from functools import partial
from http.server import ThreadingHTTPServer
from pathlib import Path
from serve import IsolatedHandler


class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(
            ('127.0.0.1', 0),
            partial(IsolatedHandler, directory=str(Path(__file__).resolve().parent)))
        cls.worker = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.worker.start()
        cls.url = f'http://127.0.0.1:{cls.server.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.worker.join()

    def test_html_is_cross_origin_isolated(self):
        with urllib.request.urlopen(self.url + '/') as response:
            self.assertEqual(response.headers['Cross-Origin-Opener-Policy'], 'same-origin')
            self.assertEqual(response.headers['Cross-Origin-Embedder-Policy'], 'require-corp')
            self.assertIn(b'Start OpenBIOS', response.read())

    def test_js_and_firmware_served(self):
        with urllib.request.urlopen(self.url + '/harness.mjs') as response:
            self.assertEqual(response.headers.get_content_type(), 'text/javascript')
        with urllib.request.urlopen(self.url + '/assets/openbios-sparc64.patched') as response:
            self.assertEqual(len(response.read()), 1593408)

    def test_wasm_mime(self):
        self.assertEqual(IsolatedHandler.extensions_map['.wasm'], 'application/wasm')


if __name__ == '__main__':
    unittest.main()
