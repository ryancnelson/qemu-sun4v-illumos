import { IMAGE_PATH, IMAGE_SIZE } from './input.mjs';
import { observeBacking } from './backing-observation.mjs';
import { captureIdentity } from './linkage.mjs';

export async function prepareBacking(mod, image, record) {
  // Hold QEMU main until the actual injected backing passes the asynchronous hash.
  mod.addRunDependency('backing-before');
  mod.FS.mkdirTree('/var/tmp');
  if (!mod.FS.isDir(mod.FS.stat('/var/tmp').mode)) throw new Error('Temporary path not directory');
  mod.FS.writeFile(IMAGE_PATH, image);
  if (mod.FS.stat(IMAGE_PATH).size !== IMAGE_SIZE) throw new Error('Backing injection size mismatch');
  const identity = captureIdentity(mod.FS);
  const observed = await observeBacking(mod.FS);
  if (!observed.matchesPinnedInput) throw new Error('Actual pre-launch backing hash mismatch');
  record(identity, observed);
  mod.removeRunDependency('backing-before');
  // Deliberately no finally-remove: failed setup must not permit launch.
}
