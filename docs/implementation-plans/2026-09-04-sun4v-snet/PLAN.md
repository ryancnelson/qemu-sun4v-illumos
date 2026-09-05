# sun4v SNET implementation plan

## Phase 1: freeze and test the FIFO contract

- Add the shared record constants and a host-side protocol model.
- Test empty reads, padding, fragmented word delivery, oversize frames, and
  recovery after malformed headers.
- Add a branch-scoped Woodpecker workflow that runs only these local tests.

## Phase 2: QEMU frontend

- Implement an eight-byte big-endian MMIO FIFO.
- Connect complete TX records and queued RX frames to QEMU `NICState`.
- Add bounded queues, reset behavior, counters, and trace events.
- Provide an application script and patch for the pinned Murayama tree.

## Phase 3: illumos GLDv3 driver

- Reuse hsimd's proven sun4v attach and hypercall conventions, not its block
  device operations.
- Register a GLDv3 Ethernet MAC and implement synchronous transmit.
- Poll the RX FIFO with a cyclic callback and deliver frames with `mac_rx()`.
- Add driver aliases and a reproducible cross-build script.

## Phase 4: lab integration

- Build both halves on Biggie through Woodpecker.
- Add `snet` to the boot archive and attach it to the existing MD node.
- Run the acceptance gates in order and preserve logs in the lab notebook.
- Only after polling works, implement and measure the q.bin/QEMU interrupt path.

