from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LAUNCHER = ROOT / "scripts" / "run-sun4v-ec2trib-login-raw-trial.sh"
ORCHESTRATOR = ROOT / "scripts" / "ec2trib-niagara-launch-unit104.sh"
WORKFLOW = ROOT / ".woodpecker" / "niagara-login-trial.yml"


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


def test_woodpecker_owns_the_openboot_transition():
    launcher = LAUNCHER.read_text()
    orchestrator = ORCHESTRATOR.read_text()
    workflow = WORKFLOW.read_text()

    assert 'CONSOLE_WAIT=${CONSOLE_WAIT:-off}' in launcher
    assert 'wait=$CONSOLE_WAIT' in launcher
    assert 'CONSOLE_WAIT=on' in orchestrator
    assert 'BOOT_HELPER=${4:-}' in orchestrator
    assert 'ec2trib-niagara-openboot.py' in workflow
    assert 'NIAGARA_OPENBOOT_COMMAND=PASS' in orchestrator
    assert '--success-marker "$LOGIN_MARKER"' in orchestrator
    assert '--timeout "$LOGIN_TIMEOUT"' in orchestrator
    assert 'NIAGARA_LOGIN_GATE=PASS' in orchestrator
