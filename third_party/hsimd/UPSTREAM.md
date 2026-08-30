# Upstream provenance

This directory preserves the complete source snapshot from:

- Repository: <https://github.com/artyom-tarasenko/hsimd>
- Commit: `a04793b34219e5c31a6c7635c512231655174a1e`
- Commit date: 2025-01-25
- Upstream subject: `RAM-Drive OpenSPARC driver for Leqion and QEMU`
- License: GNU General Public License, version 2

The snapshot was retrieved on 2026-08-30. The upstream files are preserved
unchanged. Put project modifications in explicit commits and retain the
original copyright and license notices.

## Relationship to the captured binary

The repository also contains a captured SPARC V9 kernel module at
`captures/openindiana-live-20260824/extracted/hsimd`. Its observed behavior and
provenance point to the same OpenSPARC `hsimd` driver family, but we have not
proved that it was built from this exact commit. Do not describe this snapshot
as the corresponding source for that binary until a reproducible build and
binary comparison establish the relationship.

## Build constraint

The upstream instructions require a built Solaris gate with sun4v support and
recommend building against the same Solaris release used by the target disk
image. Driver changes therefore need both source-level tests and validation
against the intended guest kernel ABI.
