import test from 'node:test';
import assert from 'node:assert/strict';
import { installKeyboardGuard } from './terminal-input.mjs';

function fixture(guarded = true) {
  let onKey = () => {}, handler = () => true;
  const output = [];
  const terminal = {
    onKey(callback) { onKey = callback; return { dispose() {} }; },
    attachCustomKeyEventHandler(callback) { handler = callback; },
  };
  if (guarded) installKeyboardGuard(terminal);
  return { output, event(type, key = '7', options = {}, emit = true) {
    const event = { type, key, code: 'Digit7', ...options,
      preventDefault() { this.defaultPrevented = true; } };
    const accepted = handler(event);
    if (accepted && emit && type !== 'keyup') {
      onKey({ key, domEvent: event });
      output.push(key);
    }
    return { accepted, event };
  } };
}

test('recorded CDP sequence demonstrates failing-before doubled data', () => {
  const f = fixture(false);
  f.event('keydown'); f.event('keypress'); f.event('keyup');
  assert.deepEqual(f.output, ['7', '7']);
});
test('same keypress after confirmed keydown sends once', () => {
  const f = fixture();
  f.event('keydown');
  const second = f.event('keypress');
  f.event('keyup');
  assert.equal(second.accepted, false);
  assert.equal(second.event.defaultPrevented, true);
  assert.deepEqual(f.output, ['7']);
});
test('normal canceled-keypress path and repeated physical keys preserved', () => {
  const f = fixture();
  f.event('keydown'); f.event('keyup'); f.event('keydown'); f.event('keyup');
  assert.deepEqual(f.output, ['7', '7']);
});
test('held-key repeats are separate keydowns', () => {
  const f = fixture();
  f.event('keydown'); f.event('keypress');
  f.event('keydown', '7', { repeat: true }); f.event('keypress');
  assert.deepEqual(f.output, ['7', '7']);
});
test('keypress-only and keydown not emitted by xterm are allowed', () => {
  const f = fixture();
  f.event('keypress'); f.event('keyup');
  f.event('keydown', '7', {}, false); f.event('keypress');
  assert.deepEqual(f.output, ['7', '7']);
});
test('different key/code/modifiers do not match', () => {
  for (const options of [{code:'Numpad7'}, {ctrlKey:true}, {altKey:true}, {metaKey:true}, {shiftKey:true}]) {
    const f=fixture(); f.event('keydown');
    assert.equal(f.event('keypress','7',options).accepted,true);
  }
  const f=fixture(); f.event('keydown'); assert.equal(f.event('keypress','8').accepted,true);
});
test('IME events are not suppressed', () => {
  const f=fixture(); f.event('keydown');
  assert.equal(f.event('keypress','7',{isComposing:true}).accepted,true);
});
test('keyup clears stale state', () => {
  const f=fixture(); f.event('keydown'); f.event('keyup');
  assert.equal(f.event('keypress').accepted,true);
});
