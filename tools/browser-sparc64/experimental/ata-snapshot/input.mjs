// Reuse the committed fixed-size/hash validator; only relocate its fixed asset URL.
import { loadImage } from '../../storage.mjs';
export { IMAGE_PATH, IMAGE_SIZE, IMAGE_SHA256, validatedImage } from '../../storage.mjs';
export function storageMode(search) {
  const values = new URLSearchParams(search).getAll('storage');
  if (values.length === 0) return false;
  if (values.length !== 1 || values[0] !== 'snapshot-sentinel') throw new Error('Unsupported storage mode');
  return true;
}
export async function selectedImage(search, fetcher = fetch) {
  if (!storageMode(search)) return null;
  return loadImage(() => fetcher(new URL('../../assets/sentinel-32k.raw', import.meta.url).href));
}
