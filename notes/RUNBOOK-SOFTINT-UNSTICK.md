# Runbook: unstick a softint-deadlocked Niagara SMP guest

Fills a gap flagged by `librarian`: *"No documented procedure for unsticking SMP
mondo deadlocks on QEMU sun4v Niagara via gdb."* The 2026-09-13 incident note
(`ARM64-SOFTINT-INCIDENT-20260913.md`) records the finding, but its one-incident
tooling (`probe-softint-wakeup.py`, `capture-softint-incident.py`) was never
committed and is gone. `tools/probe-softint-wakeup.py` here is a reconstruction,
re-verified live on 2026-09-15.

## The bug (already fixed — check before debugging)

`qemu-patches/0007-sparc-atomic-softint-updates.patch` is the fix: the timer
thread atomically sets softint bits while an MTTCG vCPU runs the set/clear
helpers, whose plain load-modify-store can overwrite an intervening timer bit.
CPU0 loses its STIMER wakeup and spins forever.

**Any image built from a commit that predates `949b1c4` has this deadlock.**
That includes `release-112` / commit `89baac8` and every GHCR tag derived from
it. Check provenance before assuming a new bug:

```sh
docker image inspect <image> --format '{{index .Config.Labels "org.opencontainers.image.revision"}}'
```

## Recognising it

Symptoms, in order of cost to check:

1. Container alive, CPU a few percent, console stops mid-boot — commonly right
   before `login:`, last line often `fcode0 is /pseudo/fcode@0`.
2. Both vCPUs pinned at the *same* PC across repeated samples, in illumos's
   interrupt disable/enable pair:

   ```
   0x0104406c:  call  0x100fc7c   ! intr_restore -> wrpr %g0,%o0,%pstate
   0x01044074:  call  0x100fc6c   ! intr_clear   -> andn %o0,2,%g1; wrpr %pstate
   0x0104407c:  ld  [ %l3 + 0x24 ], %g1
   0x01044084:  bne,pn %icc, 0x10440d4
   ```

3. `tl: 0`, `pil: 0` — nothing is masked, so the interrupt simply never arrives.
4. **The decisive check:** CPU0's `env->softint == 0x0`. The STIMER bit
   (`0x10000`) is absent. That is the sustaining condition.

Sample non-invasively with the committed QMP tool:

```sh
docker exec <container> python3 tools/qmp-live-inspect.py /state/qmp.sock \
  --command "info registers" --cpu 0 --cpu 1
```

Run it several times. A *frozen* PC means deadlock; a moving PC means it is
working, just slowly (this is emulation, not virtualisation).

### Do not be misled by `cpuq` head == tail

`info registers -a` shows `interrupts: request=2 ... cpuq=0x1d80/0x1d80`. Empty
mondo queues plus an asserted `CPU_INTERRUPT_HARD` look like a *mondo delivery*
bug and invite a wrong diagnosis against
`0006-niagara-defer-guest-mondo-in-hypervisor.patch`. It is consistent with the
lost softint bit. Confirm `softint` before blaming the mondo path.

## Unsticking a live guest

This clears the *sustaining condition* of an already-hung guest. It is **not** a
fix and must not be reported as one; the fix is patch 0007.

GDB is not in the image by default:

```sh
docker exec <container> sh -c 'apt-get update && apt-get install -y --no-install-recommends gdb'
```

Read-only inspection first:

```sh
docker cp tools/probe-softint-wakeup.py <container>:/tmp/
docker exec <container> python3 /tmp/probe-softint-wakeup.py
```

`first_cpu` is optimised out of the release build, so recover each vCPU's `env`
pointer from the live thread frames instead:

```sh
docker exec <container> gdb -q -batch -p 1 -ex "set pagination off" -ex "info threads"
```

The TCG vCPU threads report their own `env=0x...` (e.g. `cpu_exec_loop`,
`helper_ld_asi`, `helper_lookup_tb_ptr` frames). Then reassert only the timer
softint and the hard interrupt request, with all host threads stopped:

```sh
docker exec <container> gdb -q -batch -p 1 \
  -ex "set pagination off" -ex "set confirm off" \
  -ex 'set $e0 = (CPUSPARCState *)0x<CPU0_ENV>' \
  -ex 'set $c0 = (CPUState *)((char *)$e0 - (size_t)&((SPARCCPU *)0)->env + (size_t)&((SPARCCPU *)0)->parent_obj)' \
  -ex 'printf "pre: softint=0x%x irq=%d\n", $e0->softint, $c0->interrupt_request' \
  -ex 'set $e0->softint = 0x10000' \
  -ex 'set $c0->interrupt_request = 2' \
  -ex 'printf "post: softint=0x%x irq=%d\n", $e0->softint, $c0->interrupt_request'
```

Constraints, per the original incident: set **only** those two values, make no
inferior function calls, do not reset the CPU, and always detach (`-batch`
detaches on exit).

### Confirm it worked

Capture `wc -c /state/console.log` before, then after ~10s check that it grew
*and* that both PCs have moved off the spin address. Verified 2026-09-15:
console 4249 -> 4682 bytes, PCs moved from `0x1044074` to `0x10521ac` /
`0xff26eda0`, and the guest reached `oi-basecamp console login:`.

## Capture evidence before mutating

Mutating destroys the hang. Save state first:

```sh
docker exec <container> python3 tools/qmp-live-inspect.py /state/qmp.sock \
  --command "info status" --command "info cpus" --command "info registers -a" \
  --command "x/16i 0x1044060" --cpu 0 --cpu 1 > pre-unstick-state.txt
```

Note that a full guest-disk capture is large (~25 GiB for the 2026-09-13
incident) and, per that note, is private — do not publish it.
