# Narrow snv134 installed-root recovery

Owner-run candidate, pending Mica review. No helper guest execution. This reproduces the bounded service-configuration and HOME recovery already demonstrated by the owner; it does not run the finalizer or remove installer packages.

## Use

Read the script and run the default dry run as root on the intended installed system:

```sh
/usr/bin/bash ./recover.sh --dry-run
```

The script refuses anything other than SunOS 5.11 snv_134 sun4u, rpool/ROOT/opensolaris mounted at /, the pinned stock root-fs.xml, already stopped/persistently disabled media and install-setup, enabled normal console login, niagara UID101/GID10/home /home/niagara, existing nonsymlink backing directory mode0755, and a mounted ZFS /export/home. It neither creates storage nor changes permissions.

Owner must be in an exclusive recovery interval with no other repository/map/package writer. Do not run from a live installer menu contract. The script requires the installer services already disabled/stopped, rather than disabling a shell's active parent. No alternate root or /a mode exists.

Only after reviewing dry-run, owner may apply with an EXISTING snapshot of this exact root dataset and a new private evidence directory, for example ONLY if that snapshot is actually applicable and present:

```sh
/usr/bin/bash ./recover.sh --apply \
  --snapshot rpool/ROOT/opensolaris@dadcompat-firstboot \
  --evidence /var/tmp/postinstall-recovery-owner1
```

Snapshot existence is checked, not its suitability or freshness: the owner must choose an appropriate rollback point. No snapshot creation or rollback is performed. Existing evidence paths are refused. Exports can contain sensitive properties; keep the mode0700 evidence directory private and do not upload wholesale.

## Exact changes and evidence

1. Validate stock manifest SHA256 cfac5c32f4dcdb4da0ea1c774d4f0cf6f4910bb5246dc820b95de4970dbbe004 and method presence. This pins the manifest, not every guest executable.
2. Compare current composed method tuple: start fs-root/300, stop :true/0, duration transient. ONLY if this differs, verify the same tuple in last-import before permitting revert. Unrelated or missing last-import is never used. Revert can change ancestor service properties, not just one property; root, install-setup and console-login exports are preserved before mutation. Shared changes require owner review of before/after exports.
3. Revert only when needed; preserve disabled media. Explicitly enable root:default, then use svccfg refresh. Verify current and running method tuples, with at most five one-second polling intervals. Command success alone is not snapshot-update proof. Installer disables and console enable are rechecked.
4. Require exactly one old niagara entry (localhost:/export/home/&) or exactly one already-recovered entry. Unknown/duplicate entries refuse the entire operation before service mutations. Replace only the old line with:
   `niagara -fstype=lofs :/export/home/niagara`.
   Preserve all other lines, existing file mode/owner and user data; backup before change; compare for concurrent edits. This assumes the normal newline-terminated text map. No chmod/chown/account/UUID/ICT/package changes.
5. Run stock /usr/sbin/automount only after changing the map. It reconciles map mounts; no generic negative-cache-flush claim. An already-correct map needs no automount call.
6. Keep before/after evidence and primary exit status. On partial failure, stop without automatic rollback. A failed apply may have changed service state; examine private evidence before retrying. No reboot or forced restart is issued.

A success message means configuration checks passed. It does NOT prove runtime policy initialized, root method executed, all services online, HOME accessed, or a new cold boot succeeded. Owner acceptance is bounded niagara HOME access and fresh authenticated login, followed on the owner's planned boot by natural fs-root success, root/usr/RPC online, correct device policy, and svcs -xv empty. Existing owner fresh HOME login PASS and stock clean-boot PASS establish the recipe's history, not this script's native validation.

No manual device-policy edit, privilege weakening, NFS server/network/resolver change, blind devfsadm sweep, boot archive update, package removal, publisher change, or old /a shim. Retained package cleanup and original InstallationFailed history remain separate.

## Evidence/source basis

Read-only prior reports:
- /tmp/macapp-sun4u-001-remaining-cleanup-kestrel.md: actual missing start group, stock manifest, last-import ancestor effects, owner restoration.
- /tmp/macapp-sun4u-001-refresh-semantics-flint.md: action/refresh/snapshot distinction; no universal direct-svccfg claim.
- /tmp/macapp-sun4u-001-home-autofs-flint.md: actual flags5 NULL/HOST_NOT_FOUND vs flags1/0 success; exact historical parser and LOFS path; owner one-line repair and backup.
- Owner later confirms fresh HOME login PASS and stock clean boot PASS.

Historical OpenSolaris source pinned in home-autofs-flint/historical at commit 2f172c55ef76964744bc62b4500ece87f3089b4d strips the leading colon in parse_special and dispatches fstype=lofs directly to loopbackmount. Exact installed userland-source identity is not claimed. Source exclusion of loopback addresses under AI_ADDRCONFIG matches owner runtime differential; explicit LOFS avoids that local-host recognition path.

## Host validation

`python3 test_recovery.py` executes the real shell control flow in a private temporary filesystem with explicit path substitutions and command mocks. Production has no mock-path/test bypass. Tests include actual file replacement/backups/mode and user-data preservation, dry-run no mutation, conditional snapshot use, wrong version/hash, active installer refusal, absent mount/rollback, failed export, stale running snapshot stopping before map edit, duplicate/unknown/symlink map, and existing evidence preservation. This is host fixture validation, not Solaris/SMF/native validation.

## R2: interrupted map reconciliation — fail closed

R1 could change the map, receive automount exit7, then incorrectly succeed on retry because the entry was already correct. The failing-before fixture records exactly first=7, retry=0, retry automount calls=0. R1 and its original evidence are retained under R1/.

R2 creates the mode0600 file /etc/auto_home.postinstall-recovery.pending BEFORE moving the replacement map into place. It contains only the private evidence-directory path; that directory contains auto_home.before and auto_home.intended. A failed move, automount error, signal or interruption leaves this marker. Successful automount removes it. Both dry-run and apply refuse any existing marker (including a symlink) before service/file mutations. There is no automatic retry or repeated automount on every already-correct map.

Owner resolution is deliberately explicit, not a script bypass:
1. Inspect the pending marker as data, never source/execute it. Verify it and the referenced private evidence directory are the expected root-owned artifacts from this invocation. Preserve them.
2. Compare the current map with the saved before/intended maps. Unexpected edits or identity mismatches require separate owner investigation, not blind overwrite.
3. If the current map equals the reviewed intended map, the owner may run stock /usr/sbin/automount once and verify its status and bounded HOME/mount behavior. If this fails, retain the marker. If a commit never occurred, the owner must choose whether to retain the original or finish the reviewed change; R2 does not decide for them.
4. Only after explicit resolution, preserve a copy of the marker in the original private evidence directory, then remove that exact marker. A subsequent run can then verify configuration. Never remove it merely to make the script pass.

The marker is evidence of an incomplete operation, not proof the map changed or proof automount never ran. For example, interruption just after successful automount but before marker removal still intentionally requires owner resolution. No rollback or service restart is implied.

An R1 failure predating this marker cannot be detected retrospectively from map text. Resolve any known R1 partial failure from its original evidence before using R2; do not treat marker absence as proof an old execution reconciled successfully.

## R3: verified hash-provider fallback

Owner native R2 dry-run failed before mutations because Solaris digest could not find its unsigned pkcs11_softtoken provider. Owner independently ran openssl dgst -sha256 on the exact stock manifest: exit0 and the unchanged cfac5c32...be004 pin. This is provider failure, not evidence of manifest drift.

R3 uses Solaris digest first. Only a nonzero command exit triggers openssl dgst -sha256 on the same path. A successful but empty/malformed/wrong Solaris digest is refused, not hidden by a fallback. OpenSSL must exit0; its stdout must be exactly one SHA256(exact-manifest-path)= record with one 64-hex-digit value. Surrounding horizontal whitespace and hex case are normalized; missing/duplicate/multiline/wrong-file/nonhex/wrong-length records fail. The validated value must match the unchanged full pin. Stderr warnings are not parsed as digests. Nonzero OpenSSL exit fails even if stdout contains the correct digest. No provider/crypto configuration, manifest edits, or verification bypass.

Owner native rerun remains separate. R2 source/tests/docs/report are preserved under R2/. failing-before-R2-hash.txt captures the prior refusal with a failed digest and available valid OpenSSL. R3 host tests execute this fallback plus missing/malformed/bare/wrong-file/duplicate/wrong-pin/nonzero-exit refusals, and preserve the pending-reconciliation tests.

## R4: Solaris nawk portability

Owner native R3 reached the strict OpenSSL parser but Solaris /usr/bin/awk rejected sub()/tolower(); the provider fallback itself worked. Owner confirms /usr/bin/nawk is available. R4 changes exactly eight script command occurrences from awk to explicit /usr/bin/nawk, consistently covering digest parsing, mounted-root/backing checks, ownership/account checks, map classification and map rewrite. Pin, provider-success rules, strict output parser and pending reconciliation behavior are unchanged. No architecture or system configuration changes.

R3 is preserved under R3/. The new host fixture makes legacy awk reject sub/tolower while delegating other programs to the host AWK; explicit /usr/bin/nawk is relocated only in the private fixture copy to a logged wrapper that uses host /usr/bin/awk. R3 demonstrably fails before mutation in failing-before-R3-oldawk.txt. This emulates the reported incompatibility, not a complete Solaris awk implementation. The new positive fixture exercises fallback and map rewrite, requires zero legacy awk invocations and at least eight nawk invocations. Production has no path override or fallback to old awk. Owner native rerun remains separate.
