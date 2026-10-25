// xterm 5.3 normally cancels a handled keydown's browser keypress. Some CDP
// clients explicitly dispatch that keypress anyway. Suppress only that second
// event after xterm's public onKey confirms this keydown already sent a key.
// Never deduplicate serial strings: repeated keys and paste must remain intact.
export function installKeyboardGuard(terminal) {
  let handledDown;
  const signature = event => JSON.stringify([
    event.key, event.code, !!event.ctrlKey, !!event.altKey,
    !!event.metaKey, !!event.shiftKey,
  ]);
  const subscription = terminal.onKey(({ domEvent }) => {
    if (domEvent.type === 'keydown' && !domEvent.isComposing) {
      handledDown = signature(domEvent);
    }
  });
  terminal.attachCustomKeyEventHandler(event => {
    if (event.type === 'keydown' || event.type === 'keyup') handledDown = undefined;
    if (event.type === 'keypress' && !event.isComposing && handledDown === signature(event)) {
      event.preventDefault();
      return false;
    }
    return true;
  });
  return subscription;
}
