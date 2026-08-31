import copy
import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "openindiana" / "check-smf-boot-pruning.py"
MANIFEST = ROOT / "tools" / "openindiana" / "openindiana-smf-boot-pruning-v1.json"


def load_checker():
    spec = importlib.util.spec_from_file_location("check_smf_boot_pruning", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def manifest_fixture():
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


@pytest.mark.parametrize(
    "fmri,capability",
    [
        ("svc:/site/niagara-channel-shell:ch2", "channel_ppp"),
        ("svc:/network/nfs/client:default", "nfs"),
        ("svc:/system/console-login:default", "console_login"),
        ("svc:/system/cryptosvc:default", "console_login"),
        ("svc:/milestone/devices:default", "devfs"),
        ("svc:/system/filesystem/root-minimal:default", "filesystem"),
        ("svc:/system/boot-archive:default", "filesystem"),
        ("svc:/system/zfs-import:default", "zfs"),
        ("svc:/network/routing-setup:default", "networking"),
        ("svc:/network/netmask:default", "networking"),
        ("svc:/network/varpd:default", "networking"),
        ("svc:/system/system-log:default", "observability"),
    ],
)
def test_protected_service_is_rejected(fmri, capability):
    checker = load_checker()
    candidate = copy.deepcopy(manifest_fixture()["candidates"][0])
    candidate["fmri"] = fmri
    candidate["apply"] = f"svcadm disable -s {fmri}"
    candidate["rollback"] = f"svcadm enable -s {fmri}"
    with pytest.raises(checker.ManifestError, match=f"protected capability {capability}"):
        checker.validate_candidate(candidate)


def test_output_is_deterministic_and_canonically_sorted():
    checker = load_checker()
    manifest = manifest_fixture()
    first = checker.check_manifest(copy.deepcopy(manifest))
    manifest["candidates"].reverse()
    second = checker.check_manifest(manifest)
    assert first == second
    assert json.dumps(first, sort_keys=True) == json.dumps(second, sort_keys=True)
    assert [item["fmri"] for item in first["candidates"]] == sorted(
        item["fmri"] for item in first["candidates"]
    )
    assert first["status"] == "SMF_PRUNING_DRY_RUN_PASS"
    assert first["apply_allowed"] is False


def test_manifest_cannot_weaken_embedded_protection_policy():
    checker = load_checker()
    manifest = manifest_fixture()
    del manifest["protected_capabilities"]["nfs"]
    with pytest.raises(checker.ManifestError, match="protected-capability policy"):
        checker.check_manifest(manifest)
