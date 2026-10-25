# Flint postinstall recovery candidate — 2026-10-25

Ownership transferred explicitly after Kestrel confirmed no draft/directory/active edits. New isolated directory:
~/Documents/Codex/2026-08-23/run/work/maestro-sun4u-001/postinstall-recovery-flint
Historical reports and main/CI untouched. No guest actions.

Frozen for Mica review:
- recover.sh SHA256 482b7f5dffcbc15b5c9a72ec9a5cb40263b76611b9a59512d15e8abac4fac9d8
- test_recovery.py SHA256 f9d61fb522b41490669876ea88b133db80bc08fbb25ba731f147257ae92550db
- docs/README.md SHA256 5de422fdbc7760bd48655a736a20ff9f9ea44ec02bf9f3822e7af84f002c83a5
- test-results.txt SHA256 942b76aed395ba4a288ffcb2c6fc5a7bb91eecd006a49f1ddbf600f6a15ae25e

Default dry-run performs preflight only. Apply requires exact snv_134 sun4u installed ZFS root, pinned stock manifest, owner-stopped disabled media/install-setup and enabled console, exact existing UID101/GID10 backing with mounted /export/home, exact old/new map, verified existing root rollback snapshot and new private evidence directory.

Only needed last-import revert is allowed, and only after its stock method tuple is verified. Existing correct current configuration does not consult last-import. Explicit root enable and svccfg refresh are followed by current/running tuple checks; bounded stale-running refusal precedes map changes. Shared ancestor effects of revert remain explicit. Private exports and map backup precede mutations; primary exit status retained on failure; no automatic rollback.

Old niagara localhost:/export/home/& becomes only niagara -fstype=lofs :/export/home/niagara, preserving other lines, file ownership/mode and user data. Already recovered map is left alone. Stock automount runs only on map change, with no generic cache-flush claim. No source of account/ICT/package/shim/network/resolver/NFS/mode mutation, no device-policy rewrite, no reboot or forced service restart.

Validation: bash -n PASS, 13/13 real-shell host fixture tests PASS in13.926s. Tests execute a private path-relocated copy with explicit command mocks; production has no test bypass. Positive cases preserve actual fixture user data/file modes/backups. Negative cases cover wrong version/hash, absent backing mount/snapshot, active installer, export failure before mutations, stale running before map edit, duplicate/unknown/symlink map and existing evidence. These are not native SMF tests.

Owner's prior fresh HOME login PASS and clean stock boot PASS are established recipe evidence. This candidate has NOT been guest-executed. Success asserts configuration verification, not completed runtime initialization or fresh-boot acceptance. Owner must review exports and independently verify bounded HOME/login and natural boot/root/usr/RPC/policy health. Original InstallationFailed and retained package history remain unchanged.

README contains exact dry-run/apply commands, exclusivity/snapshot suitability limitations, partial-failure handling and source/report references. Review requested through Codex; no Kestrel callback or topology/CI overlap.

## R2 Mica partial-failure correction

R1 artifacts/report preserved under postinstall-recovery-flint/R1; unchanged script SHA482b7f5dffcbc15b5c9a72ec9a5cb40263b76611b9a59512d15e8abac4fac9d8. Original failing-before reproduced: mocked automount7 after map commit, retry0 with zero automount calls. failing-before-R1.txt preserves the assertion failure.

R2 chooses explicit fail-closed owner resolution, not automatic retries. A noclobber mode0600 /etc/auto_home.postinstall-recovery.pending marker containing evidence path is published BEFORE map replacement; intended map saved in private evidence. Marker persists on commit failure, signal, or automount failure, whose exit7 is preserved. Only successful automount removes marker. Any existing marker/symlink refuses both dry-run/apply before mutations; already-correct map without pending marker still skips automount. Docs give owner-only evidence comparison/reconciliation/removal procedure and warn R1 pre-marker failures cannot be detected retrospectively. No generic cache-flush or native success claim.

Validation: bash syntax PASS;15/15 shell fixture tests PASS, including first7/retry1/no retry automount/no retry mutations and preservation of preexisting marker; successful changed-map path clears marker. Initial R2 test-run exposed only fixture logger assuming a command must run; runner now handles preflight refusal with zero command calls. Initial output retained separately. No guest actions.

Exact R2 bytes:
8c4e2454e21ec4ed3e30d5493e357b37ecbbd1f02cdd93464fcc22c03f7935d3  recover.sh
88eeaa09efba08ff9b3832df1ce4a4dfb6d45c2f0718d4548a5b138595e5e36c  test_recovery.py
9e0a72f27f259069206fe5ccb9b59d35ed098e8cf6c1f2eaae16ea1e3dc89a77  docs/README.md
8a6951460e7a67b412314df8f9308faababdab35aa64fb1848755433e4e7c231  failing-before-R1.txt
9afb08438e3d3105182f61ff43d252fd15e469dd5a15e5d4ced604e1a658ca04  test-results-R2.txt
70b5ced191cd60b6371a2378884e1ed13da8de00d905794759e23cea968d5928  R2-pending.patch

## R3: verified hash-provider fallback

Owner native R2 dry-run failed before mutations because Solaris digest could not find its unsigned pkcs11_softtoken provider. Owner independently ran openssl dgst -sha256 on the exact stock manifest: exit0 and the unchanged cfac5c32...be004 pin. This is provider failure, not evidence of manifest drift.

R3 uses Solaris digest first. Only a nonzero command exit triggers openssl dgst -sha256 on the same path. A successful but empty/malformed/wrong Solaris digest is refused, not hidden by a fallback. OpenSSL must exit0; its stdout must be exactly one SHA256(exact-manifest-path)= record with one 64-hex-digit value. Surrounding horizontal whitespace and hex case are normalized; missing/duplicate/multiline/wrong-file/nonhex/wrong-length records fail. The validated value must match the unchanged full pin. Stderr warnings are not parsed as digests. Nonzero OpenSSL exit fails even if stdout contains the correct digest. No provider/crypto configuration, manifest edits, or verification bypass.

Owner native rerun remains separate. R2 source/tests/docs/report are preserved under R2/. failing-before-R2-hash.txt captures the prior refusal with a failed digest and available valid OpenSSL. R3 host tests execute this fallback plus missing/malformed/bare/wrong-file/duplicate/wrong-pin/nonzero-exit refusals, and preserve the pending-reconciliation tests.

Validation: bash -n PASS;19/19 host shell fixture methods PASS (including seven OpenSSL invalid/failure cases and four primary-output refusal cases). Runtime17.819s. No guest execution. Exact R3 bytes:
2f105fb86fecdd60679e0cf30d3c232a48ac7612670197baf816d787f5423c81  recover.sh
e07c7c20f2dba5d7ed6a0b2f1745a560250aeb213efd00d3de85eac74a48a254  test_recovery.py
52376041699633cfbb81c2855c767701711b988c8d47074b0ab733a32291d00a  docs/README.md
449e4969417216b9e06ed86fe8b49f3e175182d434e41c884176f76a4317ef81  failing-before-R2-hash.txt
9e063cd72fcf82e301f51361f9e5f3b46ad9e2e07f581f2e0cf35022fc5e6a07  test-results-R3.txt
6afeaacb77065ef1f5f7c449dd43c7f2684f2c4d11ab423c0780800819c3eb45  R3-hash-provider.patch

## R4 native Solaris AWK portability correction

Owner R3 hash fallback reached parser but old /usr/bin/awk rejected sub/tolower before mutation. R3 source/tests/docs/report preserved under R3/. R4 production delta is exactly eight awk command substitutions to explicit /usr/bin/nawk. No parser/pin/provider/pending logic changes. New fixture emulates oldawk rejection of sub/tolower; explicit nawk path relocated to a logged host wrapper only in fixture copy. Failing-before R3 exits1; passing-after fallback+apply uses zero oldawk and at least8 nawk calls. Complete20/20 fixture methods PASS; bash syntax PASS. Host fixtures do not replace owner native rerun. No guest/config/architecture changes. Exact bytes:
fb1a45a023e52e41c646ec9c666fd2394b8ddd487f26fbb4f1ddd73b71e06625  recover.sh
b4c72e090b96d895538e83f8f65f117720cbdb48ab5b108bb5b643276902e3fb  test_recovery.py
14347d3321eecbe43a493e91757fe48ffb1f49d7064d7a9e7aa55323a69ed87e  docs/README.md
11c7867d473ca2a16d253ff76d7d07b81225c0fe70962f7bd33de9cd914e2f55  failing-before-R3-oldawk.txt
792ef1ff976f1d8bebfc6de9ecbe37470f80d9245e8eff0c1235a59869ca8084  test-results-R4.txt
955b79ae3ccd0c3e34cf87cbe4dd9d082cee795a774778978b0f1c0f329757ef  R4-nawk.patch
