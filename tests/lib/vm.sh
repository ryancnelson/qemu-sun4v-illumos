#!/usr/bin/env bash
# QEMU boot helpers for niagara tests.
#
# vm_run boots QEMU against a zvol with the lock held, runs an expect
# script body, then exits QEMU cleanly via the monitor `quit` command.
# The lock is released and the clone destroyed via trap.
#
# Usage:
#   source tests/lib/vm.sh
#   vm_run <zvol-name> <expect-body>
#
# Inside the expect body, these vars are set:
#   $QEMU      — path to qemu-system-sparc64
#   $S10DIR    — path to firmware ROMs directory
#   $DEV       — /dev/zvol/... path for the zvol
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
BOOT_TIMEOUT="${BOOT_TIMEOUT:-90}"

# vm_run <zvol-name> <expect-script-body>
# Boots QEMU, runs the expect body, ensures clean exit.
# Caller is responsible for acquiring the lock and registering cleanup
# before calling vm_run.
vm_run() {
    local zvol="$1"
    local script_body="$2"
    local dev
    dev=$(zvol_path "$zvol")

    if [[ ! -b "$dev" ]]; then
        echo "ERROR: block device $dev does not exist" >&2
        return 1
    fi

    QEMU="$QEMU" S10DIR="$S10DIR" DEV="$dev" \
        expect -c "
set timeout $BOOT_TIMEOUT
$script_body
" 2>&1
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

# vm_boot_to_login <expect-continuation>
# Boots to Solaris login prompt, then runs the continuation.
# Continuation receives control after login: prompt appears.
# Expects $QEMU, $S10DIR, $DEV to be set (vm_run sets them).
vm_boot_to_login_script() {
    local continuation="$1"
    cat <<EOF
spawn \$env(QEMU) -M niagara -L \$env(S10DIR) -m 256 -nographic \\
    -drive if=pflash,file=\$env(DEV),format=raw
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
