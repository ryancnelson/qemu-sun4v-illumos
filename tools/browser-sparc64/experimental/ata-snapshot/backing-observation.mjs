import { IMAGE_PATH, IMAGE_SIZE, IMAGE_SHA256 } from './input.mjs';

// Read the actual fixed MEMFS backing file, not the original fetch buffer.
// Fixed buffer bounds the host-side read even if the backing file changed size.
export async function observeBacking(FS) {
  const stat = FS.stat(IMAGE_PATH);
  const stream = FS.open(IMAGE_PATH, 'r');
  const buffer = new Uint8Array(IMAGE_SIZE + 1);
  let count;
  try {
    count = FS.read(stream, buffer, 0, buffer.length, 0);
  } finally {
    FS.close(stream);
  }
  if (stat.size !== IMAGE_SIZE || count !== IMAGE_SIZE)
    throw new Error(`Backing size changed: stat=${stat.size} read=${count}`);
  const bytes = buffer.subarray(0, IMAGE_SIZE);
  const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
    b => b.toString(16).padStart(2, '0')).join('');
  return {kind: 'actual-MEMFS-backing-read', path: IMAGE_PATH, bytes: count, sha256,
    matchesPinnedInput: sha256 === IMAGE_SHA256};
}
