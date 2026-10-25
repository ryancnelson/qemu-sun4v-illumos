// Explicit firmware-only diagnostics; bounded and disabled by default.
export function installInputDiagnostics(terminal, element, enabled) {
  if (!enabled) return;
  let count = 0;
  const record = value => {
    if (count++ < 128) console.info('SERIAL_INPUT ' + JSON.stringify(value));
  };
  for (const type of ['keydown', 'keypress', 'beforeinput', 'input', 'keyup', 'paste']) {
    element.addEventListener(type, event => {
      const value = { type, key: event.key, code: event.code, data: event.data,
        inputType: event.inputType, trusted: event.isTrusted };
      queueMicrotask(() => record({ ...value, prevented: event.defaultPrevented }));
    }, true);
  }
  terminal.onData(data => record({ type: 'xterm.onData', data, stack: new Error().stack }));
}
