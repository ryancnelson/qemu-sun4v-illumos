import { FIRMWARE_SHA256, qemuArguments } from '../../config.mjs';
import { selectedImage } from './input.mjs';
import { overlayArguments } from './overlay-config.mjs';
import { observeBacking } from './backing-observation.mjs';
import { backingLinkage } from './linkage.mjs';
import { prepareBacking } from './prepare-backing.mjs';
import { installInputDiagnostics } from '../../input-diagnostics.mjs';
import { installKeyboardGuard } from '../../terminal-input.mjs';

const status = document.querySelector('#status');
const start = document.querySelector('#start');
let transcript = '';
let terminal;
let backingIdentity;
let runtime;
const capture = document.querySelector('#capture-backing');
capture.onclick = async () => {
  capture.disabled = true; // one bounded post-run observation
  try {
    const linkage = backingLinkage(runtime.FS, backingIdentity);
    const observed = await observeBacking(runtime.FS);
    backingLinkage(runtime.FS, backingIdentity); // also reject replacement during observation
    transcript += `BACKING_AFTER ${JSON.stringify({at: new Date().toISOString(), linkage, observed})}\n`;
    if (!observed.matchesPinnedInput) throw new Error('Actual backing content changed');
    note('Actual backing hash and same-FS/node linkage match. WRITE NOT TESTED. Save console log.');
  } catch (error) {
    transcript += `BACKING_CONTROL_FAILED ${error.message}\n`;
    note(`Backing control failed: ${error.message}. Stop; save console log.`);
  }
};
document.querySelector('#command-form').onsubmit = event => {
  event.preventDefault();
  if (!terminal) return;
  terminal.paste(document.querySelector('#command').value + '\r');
};
const note = message => { status.textContent = message; };
document.querySelector('#reload').onclick = () => location.reload();
document.querySelector('#download').onclick = () => {
  const url = URL.createObjectURL(new Blob([transcript], { type: 'text/plain' }));
  const a = document.createElement('a');
  a.href = url; a.download = 'sparc64-openbios-console.txt'; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};

async function verifiedFirmware() {
  const response = await fetch('../../assets/openbios-sparc64.patched');
  if (!response.ok) throw new Error(`Firmware fetch: HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  const hex = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
  if (hex !== FIRMWARE_SHA256) throw new Error(`Firmware provenance mismatch: ${hex}`);
  return bytes;
}

start.onclick = async () => {
  start.disabled = true;
  document.querySelector('#ram').disabled = true;
  try {
    if (!globalThis.crossOriginIsolated || typeof SharedArrayBuffer === 'undefined') {
      throw new Error('Cross-origin isolation missing. Serve with serve.py on localhost; do not open file://.');
    }
    note('Loading local runtime and verifying run 132 firmware…');
    await import('../../vendor/xterm.js');
    await import('../../vendor/xterm-pty.js');
    if (!globalThis.Terminal || !globalThis.openpty) throw new Error('Missing xterm / xterm-pty globals');
    const { default: createQemu } = await import('../../assets/qemu-system-sparc64.js');
    const firmware = await verifiedFirmware();
    const image = await selectedImage(location.search);
    const extraArguments = overlayArguments(image !== null, Number(document.querySelector('#ram').value));
    terminal = new Terminal({ cols: 100, rows: 32, scrollback: 20000, convertEol: false });
    terminal.open(document.querySelector('#terminal'));
    installKeyboardGuard(terminal);
    installInputDiagnostics(terminal, document.querySelector('#terminal'),
      new URLSearchParams(location.search).get('inputDiagnostics') === '1');
    const { master, slave } = openpty();
    // Capture serial output without altering the PTY's terminal translation.
    const write = terminal.write.bind(terminal);
    const decoder = new TextDecoder();
    terminal.write = (data, callback) => {
      transcript += typeof data === 'string' ? data : decoder.decode(data, { stream: true });
      write(data, callback);
    };
    terminal.loadAddon(master);
    const module = {
      arguments: [...qemuArguments(Number(document.querySelector('#ram').value)), ...extraArguments],
      pty: slave,
      mainScriptUrlOrBlob: new URL('../../assets/qemu-system-sparc64.js', import.meta.url).href,
      locateFile: name => new URL(`../../assets/${name}`, import.meta.url).href,
      print: line => { transcript += `${line}\n`; terminal.writeln(line); },
      printErr: line => { transcript += `${line}\n`; terminal.writeln(line); },
      onAbort: reason => note(`QEMU aborted: ${reason}. Save the console log, then reload.`),
      onExit: code => note(`QEMU exited (${code}). Reload before restarting.`),
      preRun: [mod => {
        mod.FS.mkdirTree('/firmware');
        mod.FS.writeFile('/firmware/openbios-sparc64', firmware);
        if (image) {
          prepareBacking(mod, image, (identity, observed) => {
            backingIdentity = identity;
            transcript += `BACKING_BEFORE ${JSON.stringify({at: new Date().toISOString(), inode: backingIdentity.inode, observed})}\n`;
          }).catch(error => {
            // Keep launch dependency blocked on failure; never launch with an unverified backing.
            transcript += `BACKING_CONTROL_FAILED ${error.message}\n`;
            note(`Pre-launch backing check failed: ${error.message}. Reload; QEMU launch held.`);
          });
        }
      }],
    };
    transcript += `Firmware SHA256 ${FIRMWARE_SHA256}\nArguments ${JSON.stringify(module.arguments)}\n`;
    note('Starting QEMU in its Emscripten pthread worker…');
    const instance = await createQemu(module);
    runtime = instance;
    // Match qemu-wasm's xterm-pty workaround; use the resolved module exports.
    const oldPoll = instance.TTY.stream_ops.poll;
    instance.TTY.stream_ops.poll = function(stream, timeout) {
      if (!slave.readable) return (slave.writable ? 4 : 0);
      return oldPoll.call(this, stream, timeout);
    };
    globalThis.qemuHarness = { instance, arguments: module.arguments, firmwareSha256: FIRMWARE_SHA256 };
    terminal.focus();
    document.querySelector('#send-command').disabled = false;
    capture.disabled = !image;
    note('Runtime initialized. Firmware boot is proven only when its prompt appears; try 1 2 + .');
  } catch (error) {
    console.error(error);
    note(`Start failed: ${error.message}. Reload after correcting the cause.`);
  }
};
