import { IMAGE_PATH } from './input.mjs';

export function captureIdentity(FS) {
  const node = FS.lookupPath(IMAGE_PATH, {follow: true}).node;
  return {FS, node, inode: node.id};
}
export function backingLinkage(FS, identity) {
  if (FS !== identity.FS) throw new Error('Filesystem instance changed');
  const node = FS.lookupPath(IMAGE_PATH, {follow: true}).node;
  if (node !== identity.node || node.id !== identity.inode) throw new Error('Backing node replaced');
  if (FS.streams.length > 128) throw new Error('Stream observation exceeds bound');
  const backing = FS.streams.filter(s => s && (s.path === IMAGE_PATH || s.node === node));
  if (!backing.length || backing.some(s => s.node !== node || s.path !== IMAGE_PATH || s.isWrite))
    throw new Error('No consistent read-only QEMU backing stream');
  const temporary = FS.streams.filter(s => s && /^\/var\/tmp\/vl\.[A-Za-z0-9]+$/.test(s.path));
  const describe = s => ({fd: s.fd, path: s.path, inode: s.node.id, flags: s.flags, writable: s.isWrite});
  return {sameFilesystem: true, sameBackingNode: true, inode: identity.inode,
    backingStreams: backing.map(describe), temporaryStreams: temporary.map(describe),
    limit: 'Stream metadata, not an inspected QEMU block graph or write-isolation proof'};
}
