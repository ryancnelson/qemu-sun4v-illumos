#!/usr/bin/env bash
# Take a bare Ubuntu 24.04 (or Debian 12) host to a working Niagara/Solaris host.
#
#   $ git clone <repo> && cd <repo>
#   $ ./setup-host.sh              # preflight + deps + build patched QEMU
#   $ ./setup-host.sh --check      # preflight only, changes nothing
#
# WHAT THIS DOES NOT DO. It cannot give you Solaris. Oracle-licensed media and the
# OpenSPARC T1 firmware must be supplied by you; section 5 of SPEC-portable.md explains
# why, and the end of this script tells you exactly what to put where.
#
# VERIFIED end to end on Ubuntu 24.04.3 LTS arm64 under UTM, ~2 minutes:
#     QEMU emulator version 8.2.2 (v8.2.2-dirty), ELF 64-bit ARM aarch64
#     niagara machine types: 1, MAP_SHARED occurrences in niagara.c: 7
#     meson 1.3.2 (the gate below wants >= 0.63; Debian 11's was too old)
# /dev/ppp is present on both Ubuntu 24.04 and Debian 11 arm64, so IP to the guest
# needs no rework on this route.
#
# DISK NOTE FOR UBUNTU SERVER INSTALLS. The installer leaves roughly half the disk
# unallocated by default, so a 30 GB virtual disk presents as a 14 GB filesystem with
# ~7 GB free -- not enough. You do NOT need to resize the virtual disk or reboot; the
# space is already in the volume group:
#     sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
#     sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
# That took root from 14G to 27G online, on a running system.
#
# DESIGN RULES, learned the hard way in this project:
#  * Preflight FAILS on insufficient RAM. A 973 MB VM looked fine and then OOM'd the
#    guest at boot -- an early hard error beats a confusing one later.
#  * Every step VERIFIES by measurement, not by exit status. curl exits 0 having saved
#    an HTML error page; a cp can silently not happen; an apt install can be a no-op.
#  * Idempotent throughout. Re-running is the supported way to resume a failed run.
#  * NO ZFS. It is used here only for snapshots, and zfs-dkms is a slow kernel-module
#    build on arm64. Snapshots use cp --reflink=auto instead.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QEMU_VER="${QEMU_VER:-8.2.2}"
QEMU_SRC="${QEMU_SRC:-$REPO/qemu}"
DATA="${DATA:-$HOME/niagara}"
MIN_RAM_MB=2500
MIN_DISK_GB=20

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

say()  { printf '\n=== %s ===\n' "$*"; }
ok()   { printf '  [ ok ] %s\n' "$*"; }
warn() { printf '  [warn] %s\n' "$*"; }
die()  { printf '  [FAIL] %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight ----
say "preflight"

arch="$(uname -m)"
case "$arch" in
    aarch64|arm64) ok "arch $arch (Apple silicon via UTM is the reference target)" ;;
    x86_64)        ok "arch $arch" ;;
    *)             die "unsupported arch $arch" ;;
esac
# qemu-system-sparc64 is TCG on every host -- there is no sun4v hardware virtualisation
# to lose, so an emulated-in-a-VM setup costs nothing extra.

ram_mb=$(free -m | awk '/^Mem:/{print $2}')
if (( ram_mb < MIN_RAM_MB )); then
    die "only ${ram_mb} MB RAM. The guest alone wants 1024 MB of ANONYMOUS memory, plus
         QEMU overhead, plus page cache for a 2.5 GB MAP_SHARED disk image. Give the VM
         4 GB. (Measured: a 973 MB host cannot boot this guest.)"
fi
ok "ram ${ram_mb} MB"

disk_gb=$(df -BG --output=avail "$HOME" | tail -1 | tr -dc '0-9')
if (( disk_gb < MIN_DISK_GB )); then
    warn "only ${disk_gb} GB free on \$HOME. Budget: QEMU build tree ~2 GB, guest image
         2.5 GB, each snapshot up to 2.5 GB unless the filesystem supports reflinks."
else
    ok "disk ${disk_gb} GB free"
fi

if [[ -c /dev/ppp ]]; then
    ok "/dev/ppp present (IP to the guest will work)"
else
    warn "/dev/ppp missing. 'sudo modprobe ppp_generic' may fix it. Without it the BBS
         channel still works -- ASK, GET and a shell over a channel -- but STARTPPP
         cannot bring up IP."
fi

command -v sudo >/dev/null || die "sudo not installed"
sudo -n true 2>/dev/null && ok "passwordless sudo" || warn "sudo will prompt for a password"

if (( CHECK_ONLY )); then
    say "check only - stopping here, nothing changed"
    exit 0
fi

# --------------------------------------------------------------- packages ----
say "packages"

PKGS=(
    # building our patched QEMU
    build-essential ninja-build meson pkg-config python3 python3-venv
    libglib2.0-dev libpixman-1-dev zlib1g-dev libslirp-dev
    # the tooling in tools/
    socat expect tmux python3-pip git curl
    # PPP peer for the guest
    ppp
    # package extraction from Solaris media: 7z for repacked ISOs, cpio for pkgs
    p7zip-full cpio
)
missing=()
for p in "${PKGS[@]}"; do
    dpkg -l "$p" 2>/dev/null | grep -q '^ii' || missing+=("$p")
done
if (( ${#missing[@]} )); then
    echo "  installing: ${missing[*]}"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
fi
# Verify by measurement: apt can succeed while a package stays unconfigured.
still=()
for p in "${PKGS[@]}"; do
    dpkg -l "$p" 2>/dev/null | grep -q '^ii' || still+=("$p")
done
(( ${#still[@]} )) && die "packages still not installed: ${still[*]}"
ok "all ${#PKGS[@]} packages present"

# meson is the version wall that bites on older distros; QEMU 8.2 needs >= 0.63.
mv=$(meson --version)
printf '  meson %s ' "$mv"
if [[ "$(printf '%s\n0.63.0\n' "$mv" | sort -V | head -1)" == "0.63.0" ]]; then
    echo "(>= 0.63 required, ok)"
else
    die "meson $mv is too old for QEMU $QEMU_VER (needs >= 0.63). Try:
         python3 -m venv ~/.venv-meson && ~/.venv-meson/bin/pip install meson ninja"
fi

# ------------------------------------------------------------------- qemu ----
say "patched qemu $QEMU_VER"

# THE PATCH IS NOT OPTIONAL. Stock QEMU's niagara machine never writes the vdisk back,
# so every change the guest makes is lost. patches/0001 makes the disk a MAP_SHARED
# mapping of a regular file, which is also what the P2-014 channels depend on.
if [[ ! -d "$QEMU_SRC/.git" && ! -f "$QEMU_SRC/configure" ]]; then
    echo "  cloning qemu v$QEMU_VER (shallow)"
    git clone --depth 1 --branch "v$QEMU_VER" \
        https://gitlab.com/qemu-project/qemu.git "$QEMU_SRC"
fi

cd "$QEMU_SRC"
if grep -q 'niagara_vdisk_writeback\|MAP_SHARED' hw/sparc64/niagara.c 2>/dev/null; then
    ok "vdisk patch already applied"
else
    echo "  applying patches/0001-niagara-vdisk-writeback.patch"
    git apply --3way "$REPO/patches/0001-niagara-vdisk-writeback.patch" \
        || die "patch did not apply against v$QEMU_VER. If you changed QEMU_VER, the
                patch may need rebasing; hw/sparc64/niagara.c is the only file it
                touches."
    grep -q 'MAP_SHARED' hw/sparc64/niagara.c \
        || die "patch reported success but MAP_SHARED is absent from niagara.c"
    ok "vdisk patch applied and verified present"
fi

BIN="$QEMU_SRC/build/qemu-system-sparc64"
if [[ -x "$BIN" ]] && "$BIN" --version >/dev/null 2>&1; then
    ok "qemu already built: $("$BIN" --version | head -1)"
else
    echo "  configuring (sparc64 only, minimal features - this keeps the build short)"
    mkdir -p build && cd build
    ../configure --target-list=sparc64-softmmu \
        --disable-docs --disable-gtk --disable-sdl --disable-vnc \
        --disable-spice --disable-opengl --disable-vte --disable-curses \
        --disable-libssh --disable-bzip2 --disable-snappy --disable-lzo \
        --enable-slirp > /tmp/qemu-configure.log 2>&1 \
        || { tail -20 /tmp/qemu-configure.log; die "configure failed"; }
    echo "  building with $(nproc) jobs (grab a coffee)"
    ninja -j"$(nproc)" > /tmp/qemu-build.log 2>&1 \
        || { tail -30 /tmp/qemu-build.log; die "build failed"; }
    [[ -x "$BIN" ]] || die "build finished but $BIN does not exist"
    ok "built: $("$BIN" --version | head -1)"
fi

# Prove the machine type we need is actually present, rather than assuming.
"$BIN" -M help 2>/dev/null | grep -q niagara \
    || die "this qemu has no 'niagara' machine type"
ok "machine type 'niagara' available"

# ------------------------------------------------------------------ layout ----
say "data layout (no zfs)"
mkdir -p "$DATA"/{images,firmware,media,logs,delivery}
ok "$DATA/{images,firmware,media,logs,delivery}"

# ------------------------------------------------------------ what you owe ----
say "what you must supply"
cat <<EOF
  This script cannot legally fetch these for you.

  1. OpenSPARC T1 firmware  ->  $DATA/firmware/
       Needs the reset/hypervisor image (q.bin) and a machine-description blob.
       From Oracle's OpenSPARC T1 architecture package. md/*.pdesc in this repo
       regenerate the MD byte-identically via tools/build-mdgen.sh, so you need the
       upstream package, not our copies.

  2. Solaris 10 SPARC media  ->  $DATA/media/
       ISOs. tools/iso-extract.py pulls individual packages from a local ISO or a URL.

  3. A guest image  ->  $DATA/images/primary.img
       Either one you build from the media above, or one you already have. It MUST be a
       regular file, never a block device: the vdisk is a MAP_SHARED mapping and the
       channels depend on that. tools/ has the VTOC, UFS and toolchain scripts.

  Then:
      sudo bash tools/chan/host-up.sh            # channel bridges (+ PPP if /dev/ppp)
      BBS_LLM_URL=<your endpoint> sudo -E python3 tools/chan/host-bbs.py /run/niag1
EOF

say "host ready"
