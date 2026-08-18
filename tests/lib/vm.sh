#!/usr/bin/env bash
# QEMU boot helpers for niagara tests.
#
# vm_run boots QEMU against a disk image with the lock held, runs an expect
# script body, then exits QEMU cleanly via the monitor `quit` command.
# The lock is released and the clone destroyed via trap.
#
# Usage:
#   source tests/lib/vm.sh
#   vm_run <disk-name> <expect-body>
#
# Inside the expect body, these vars are set:
#   $QEMU      — path to qemu-system-sparc64
#   $S10DIR    — path to firmware ROMs directory
#   $DEV       — path to the disk image FILE (P2-012, was /dev/zvol/...)
#
# The expect body must exit the process; vm_run does not add a trailing
# quit. To exit cleanly from an expect script:
#   send "\x01c"    ;# Ctrl-A c — enter monitor
#   expect "(qemu)"
#   send "quit\r"
#   expect eof

set -euo pipefail

QEMU="${QEMU_BIN:-qemu-system-sparc64}"
S10DIR="${S10DIR:-/datapool/niagara/base}"
# Generous: every boot loads the whole vdisk into RAM (2-2.5GB) and the
# atexit writeback pushes it all back, so a boot can take well over a
# minute under load. A too-tight timeout made test-disk-writes-persist
# flaky, and because `out=$(vm_run ...)` aborted under `set -e` before
# the transcript was echoed, the failure produced NO diagnostics at all.
BOOT_TIMEOUT="${BOOT_TIMEOUT:-180}"

# Guest RAM in MB. Default 256 to preserve existing test behaviour.
#
# 1024 works: Artyom Tarasenko's sun4v MD files raise the ceiling to 1GiB, and
# `prtconf` inside Solaris 10 confirms "Memory size: 1024 Megabytes". Those MD
# files are a DROP-IN -- openboot.bin, q.bin, nvram1 and reset.bin are all
# byte-identical to ours; only 1up-md.bin and 1up-hv.bin differ. So 1GiB is
# purely a Machine Description change, selected via S10DIR:
#     NIAGARA_MEM=1024 S10DIR=/datapool/niagara/base-1gib
# Source: github.com/artyom-tarasenko/qemu-sun4v-md @ 1GiB-experimental
MEM="${NIAGARA_MEM:-256}"

# VM_TRANSCRIPT: path to append a LIVE copy of the transcript to.
#
# Callers capture vm_run with `out=$(vm_run ...)`, which buffers the whole
# transcript until the run ends -- so a tmux pane shows nothing for minutes,
# and a stall-detecting poller (tools/waitfor.sh) watching the caller's log
# sees a file that never grows and declares a false stall. Point
# VM_TRANSCRIPT at a file to get output in real time, so a human can watch
# and waitfor can tell "slow" from "dead".

# vm_run <disk-name> <expect-script-body>
# Boots QEMU, runs the expect body, ensures clean exit.
# Caller is responsible for acquiring the lock and registering cleanup
# before calling vm_run.
vm_run() {
    local disk="$1"
    local script_body="$2"
    local dev
    dev=$(disk_path "$disk")

    # P2-012: a regular FILE, not a block device.
    if [[ ! -f "$dev" ]]; then
        echo "ERROR: disk image $dev does not exist (or is not a regular file)" >&2
        return 1
    fi

    QEMU="$QEMU" S10DIR="$S10DIR" DEV="$dev" MEM="$MEM" \
        expect -c "
set timeout $BOOT_TIMEOUT
$script_body
" 2>&1 | tee -a "${VM_TRANSCRIPT:-/dev/null}"
}

# vm_quit_fragment — expect fragment: enter QEMU monitor, quit.
#
# Use ONLY when the guest never reached a shell (e.g. OBP-only tests).
# If the guest booted to a shell, use $vm_clean_shutdown_fragment instead,
# or the LUFS journal is left dirty and the NEXT boot panics in ufs:fetchbuf.
vm_quit_fragment='
    send "\x01c"
    expect {
        "(qemu)" {
            send "quit\r"
            expect eof
        }
        timeout {
            puts "OBSERVED: timed out waiting for QEMU monitor"
        }
    }
'

# vm_clean_shutdown_fragment — REQUIRED exit path for any test that reached
# a Solaris shell prompt.
#
# "lockfs -f /" commits the UFS logging (LUFS) journal. Without it, the
# atexit writeback persists a disk image with a dirty journal, and the next
# boot panics replaying it:
#     BAD TRAP type=10 ufs:fetchbuf -> readlog -> vfs_mountroot
#
# EXPECT DISCIPLINE: match the shell prompt, never an echo-able marker.
# The tty echoes every command as it is typed, so `send "... && echo DONE"`
# followed by `expect "DONE"` matches the ECHO of the command line and returns
# before the shell has run anything. That silently broke this harness: QEMU was
# quit before lockfs ran, and no data reached the disk. The prompt "#" only
# appears once a command has actually completed.
vm_clean_shutdown_fragment='
    send "lockfs -f / && sync\r"
    expect {
        "# " {
            puts "OBSERVED: lockfs+sync returned to prompt (journal committed)"
        }
        timeout {
            puts "OBSERVED: WARNING lockfs did not return — zvol may be dirty"
        }
    }
    send "\x01c"
    expect {
        "(qemu)" {
            send "quit\r"
            expect eof
        }
        timeout {
            puts "OBSERVED: timed out waiting for QEMU monitor"
        }
    }
'

# vm_halt_writeback_fragment — exit path for tests that reached a shell.
#
# Prefer this over $vm_clean_shutdown_fragment. Two findings force it:
#
# 1. "lockfs -f /" is NOT sufficient. It commits the LUFS journal, but the
#    shell and syslog re-dirty it before QEMU is killed, so the next boot can
#    panic replaying it (BAD TRAP type=10, ufs:readlog -> lufs_read_strategy
#    -> vfs_mountroot). `init 5` runs the real shutdown: it stops services,
#    prints "syncing file systems... done", and halts at OBP.
#
# 2. The Ctrl-A monitor escape does NOT reach QEMU from a scripted expect.
#    With no `interact`, "\x01c" is delivered to the guest, which echoed it
#    verbatim at the OBP prompt ("ok s^Ac") while expect waited forever for a
#    "(qemu)" prompt that never came. Signal the spawned QEMU pid instead:
#    SIGTERM runs a normal exit(), so the atexit writeback fires. SIGKILL
#    would silently discard every write.
#
# Requires $qpid, set by vm_boot_to_login_script right after spawn.
vm_halt_writeback_fragment='
    send "init 5\r"
    expect {
        -re "syncing file systems\.\.\. done" {
            puts "OBSERVED: guest synced filesystems"
        }
        "Program terminated" {
            puts "OBSERVED: guest halted at OBP"
        }
        timeout {
            puts "OBSERVED: WARNING init 5 did not report a sync"
        }
    }
    sleep 2
    exec kill -TERM $qpid
    expect {
        "writeback complete" {
            puts "OBSERVED: vdisk writeback complete"
        }
        eof {
            puts "OBSERVED: qemu exited (writeback not seen in transcript)"
        }
        timeout {
            puts "OBSERVED: WARNING writeback never reported"
        }
    }
    catch { expect eof }
'

# vm_boot_to_login <expect-continuation>
# Boots to Solaris login prompt, then runs the continuation.
# Continuation receives control after login: prompt appears.
# Expects $QEMU, $S10DIR, $DEV to be set (vm_run sets them).
vm_boot_to_login_script() {
    local continuation="$1"
    cat <<EOF
spawn \$env(QEMU) -M niagara -L \$env(S10DIR) -m \$env(MEM) -nographic \\
    -drive if=pflash,file=\$env(DEV),format=raw
set qpid [exp_pid]
expect {
    "ok" {
        send "boot disk\r"
    }
    timeout {
        puts "OBSERVED: timed out waiting for OBP ok prompt"
        exit 1
    }
}
expect {
    "login:" {
        puts "OBSERVED: login prompt"
    }
    "Can't open boot" {
        puts "OBSERVED: boot device error"
        exit 1
    }
    timeout {
        puts "OBSERVED: timed out waiting for login prompt"
        exit 1
    }
}
$continuation
EOF
}
