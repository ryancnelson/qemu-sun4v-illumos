# Niagara SMP OCI test requirements

| Requirement | Automated evidence |
| --- | --- |
| Pinned patched QEMU | Docker build verifies patch checksums and applies each patch |
| Two guest CPUs | Entrypoint policy test plus `psrinfo` guest gate |
| Matched two-CPU firmware | MD/HV source and binary checksum checks |
| No KMDB | OpenBoot policy test and negative console-signature gate |
| Automatic boot | Existing `APPLIANCE_AUTO_BOOT=PASS` login smoke |
| Existing package behavior | Complete repository unit suite and Woodpecker self-contained test |

The final Woodpecker transcript is the human-visible acceptance record.  No
manual console input is part of the test.
