from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WRAPPER = ROOT / "scripts" / "ec2trib-niagara-host-dtrace.sh"


def test_qemu_identity_uses_procfs_executable_link_not_full_pargs_line():
    text = WRAPPER.read_text()

    assert '/proc/$QEMU_PID/path/a.out' in text
    assert "readlink" in text
    assert "pargs -l" not in text
