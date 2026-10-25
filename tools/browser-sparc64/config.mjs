export const FIRMWARE_SHA256 = '1341c4195b245c4573fdff53c64f775f8a222c5f5432da52d5937a1ead2e3938';
export function qemuArguments(ramMiB = 512) {
  if (![128, 256, 512, 1024, 1536].includes(ramMiB)) throw new Error('Unsupported guest RAM');
  return [
    '-M', 'sun4u', '-m', String(ramMiB), '-smp', '1',
    '-accel', 'tcg,tb-size=64,thread=multi',
    '-vga', 'none', '-display', 'none', '-monitor', 'none',
    '-serial', 'stdio', '-nic', 'none',
    '-bios', '/firmware/openbios-sparc64',
    '-prom-env', 'input-device=ttya', '-prom-env', 'output-device=ttya',
    '-prom-env', 'auto-boot?=false',
  ];
}
