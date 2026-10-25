export function overlayArguments(enabled, ram) {
  if (typeof enabled !== 'boolean') throw new Error('Invalid overlay selection');
  if (!enabled) return [];
  if (ram !== 512) throw new Error('Overlay control requires 512 MiB');
  return ['-drive', 'file=/sentinel.raw,format=raw,if=ide,index=0,media=disk,snapshot=on,readonly=off'];
}
