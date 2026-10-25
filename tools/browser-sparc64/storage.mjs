// Fixed sentinel input only: no caller-supplied URL, path or argv.
export const IMAGE_SIZE = 32768;
export const IMAGE_SHA256 = '52fa9b2c6313c7c50f430ea508815b0c1ed2bf7a5978ffb2131c21acffa5bdf5';
export const IMAGE_PATH = '/sentinel.raw';
export function storageMode(search) {
  const values = new URLSearchParams(search).getAll('storage');
  if (values.length === 0) return false;
  if (values.length !== 1 || values[0] !== 'sentinel') throw new Error('Unsupported storage mode');
  return true;
}
export function storageArguments(enabled) {
  if (typeof enabled !== 'boolean') throw new Error('Storage enable must be boolean');
  return enabled ? ['-drive', 'file=/sentinel.raw,format=raw,if=ide,index=0,media=cdrom,readonly=on'] : [];
}
export async function validatedImage(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength !== IMAGE_SIZE) throw new Error('Invalid sentinel image size/type');
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('');
  if (hash !== IMAGE_SHA256) throw new Error('Sentinel image hash mismatch');
  return bytes;
}
export async function loadImage(fetcher = fetch) {
  const response = await fetcher('./assets/sentinel-32k.raw');
  if (!response.ok) throw new Error('Sentinel image fetch failed');
  if (response.headers.get('content-length') !== String(IMAGE_SIZE)) throw new Error('Sentinel image length header mismatch');
  const reader = response.body.getReader();
  const bytes = new Uint8Array(IMAGE_SIZE);
  let offset = 0;
  try {
    for (;;) {
      const {value, done} = await reader.read();
      if (done) break;
      if (offset + value.byteLength > IMAGE_SIZE) throw new Error('Sentinel image exceeds bound');
      bytes.set(value, offset); offset += value.byteLength;
    }
  } finally { await reader.cancel(); }
  if (offset !== IMAGE_SIZE) throw new Error('Truncated sentinel image');
  return validatedImage(bytes);
}
export async function selectedImage(search, fetcher = fetch) {
  return storageMode(search) ? loadImage(fetcher) : null;
}
