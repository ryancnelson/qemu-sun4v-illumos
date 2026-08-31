from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "scripts" / "run-sun4v-ec2trib-login-raw-trial.sh"


def test_tmpfs_unit100_uses_host_page_cache_but_persistent_disks_do_not():
    text = LAUNCHER.read_text()

    carrier = next(line for line in text.splitlines()
                   if 'id=carrier100,format=raw' in line)
    installer = next(line for line in text.splitlines()
                     if 'id=installer103,format=raw' in line)
    target = next(line for line in text.splitlines()
                  if 'id=target104,format=raw' in line)

    assert "cache=writeback" in carrier
    assert "cache=none" not in carrier
    assert "cache=none" in installer
    assert "cache=none" in target
