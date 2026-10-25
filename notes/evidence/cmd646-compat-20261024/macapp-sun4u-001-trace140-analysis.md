# Flint — frozen run140 independent findings

Confirmed the positive pending-bit transition in the actual frozen trace. SHA256 ad83fa56689621fae3b8de8cd722feb99069490ba3e54ae27a177fa6b628bb16, 67302187 bytes, 633551 lines independently match the owner. Raw remains unchanged. Capture is **incomplete**, not a boot verdict.

## Decisive ordered evidence

Raw line numbers are file record positions, not the prefix emitter ID 9.

- 469462: BMDMA offset 0x1 write 0x10. This is the MRDMODE primary interrupt-block mask; the BMDMA payload itself omits controller identity.
- 469464–469467: same PIO bus 0xca2d96014600, Device/Head 0xe0 (master), Features 0x03, Sector Count 0x42, Command 0xef (SET FEATURES).
- 469468 at 1792902181.533575: cmd646-ide 01:03.0 CFR offset 0x50 reads 0x04.
- 469469/469470 at 1792902181.533600/.533618: two ordinary STATUS reads on that PIO bus return 0x50.
- 469471: Device/Head write 0xe0.
- 469472 at 1792902181.533635: same BDF CFR reads 0x00. Further zero reads appear in the preserved window through 469480.

There is no intervening logged W1C or other controller write between the two cited CFR reads; the only intervening write is Device/Head. A positive CFR pending indication becomes zero across the two ordinary STATUS reads and selection write. This supports the proposed consumer interaction; it does not independently identify which operation caused the transition or prove a hardware defect. Primary interrupt blocking makes pending indication especially distinct from IRQ output.

## Exact original uata width and association

Original uata module SHA256 9e35734e519342fe1af436108936afd8c71f2f4958586e5806ec7ace7a1987aa. First/second callbacks at .text offsets 0x2f2c/0x2fb8 both use controller+0x690, bound by cmd_init to cmd_get_intr_status. Primary callback polls config+0x50 mask 0x04; secondary polls config+0x57 mask 0x10. Both call ata_wait, whose 0x2bf4 relocation is **ddi_get8**: requested width is **one byte**. The intervening status access is also ddi_get8. Detailed immutable derivation: run140-preparation/width-evidence.json.

This exact callback sequence supports a bounded same-run inference associating the cited PIO command with BDF 01:03.0 primary-channel polling. It is not a direct pointer-to-BDF join: selected events omit that link, runtime PC, and PCI transaction width. No global pointer mapping or blanket byte-width rule was installed. The first Device/Head event carries the pre-selection IDEState pointer; subsequent feature/command events carry 0xca2d96014688.

## Reused parse and limits

Reused owner work/b134-resume/run140/parsed/findings.json and full ordered timeline.jsonl; no second large parse or sampling. Findings confirm 633551 selected records, zero unparsed selected records, one SET FEATURES, empty mapping, and owner-declared incomplete capture. Owner reports parser exit 2; that is not a boot result. Parser conservatively leaves controller polls unassociated. Mica independently counted 164080 zero polls from 469472 to EOF with no logged W1C; that tail count is attributed to Mica, not a new Flint recount.

Captured ordering is valid positive evidence despite the cap. There are no direct GPIO/INTA observations, no proof of STATUS-retained hardware latch semantics, and no completed second-poll timeout/warning or whole-boot conclusion from this window. Do not claim absence beyond capture, proven boot-failure causation, or that the separately approved ack-only patch fixes B134.

## Artifacts

Owned directory: /Users/ryan/Documents/Codex/2026-08-23/run/work/maestro-sun4u-001/trace-parser/run140-analysis.
raw-window.txt preserves exact ordered lines 469448–469480 with timestamps.
independent-findings.json records provenance, positive transition, width basis, mapping uncertainty and limits.
SHA256SUMS binds both owned artifacts and this report.
Original parser, tests, ack-only patch, firmware artifacts and owner raw/timeline remain unchanged.
