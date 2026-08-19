#!/usr/bin/env bash
# update.sh -- refresh the host-side tooling from the upstream repo.
#
#   $ ~/sun4v/update.sh                 # pull, report, rebuild only if needed
#   $ ~/sun4v/update.sh --check         # say what would change, touch nothing
#
# WHY THIS EXISTS. The shipped VM is a multi-gigabyte artifact dominated by one 2.5 GB
# Solaris image that essentially never changes. The tooling around it is a megabyte of
# scripts that changes constantly. Re-downloading the VM to get a script fix would be
# absurd, so the image ships once and the tools update over git.
#
# WHAT IT DELIBERATELY DOES NOT TOUCH:
#   * the guest image -- your work lives in there, and it is not in git
#   * anything inside the guest. Guest-side helpers (/opt/niag/bin) are installed FROM
#     the repo but updating them means writing into a live Solaris filesystem, which is
#     a separate, riskier operation. Run tools/chan/guest-install.sh yourself for that.
#   * the built QEMU, unless a patch actually changed -- a rebuild is minutes.
set -uo pipefail

REMOTE="${NIAGARA_REMOTE:-}"
PROJ="${NIAGARA_PROJ:-$HOME/niag-proj}"
CHECK=0
[[ "${1:-}" == "--check" ]] && CHECK=1

die() { printf '  FAIL  %s\n' "$*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

if [[ -z "$REMOTE" ]]; then
    cat >&2 <<'EOF'
  No upstream configured. Set it once:

    echo 'export NIAGARA_REMOTE=https://github.com/USER/REPO.git' >> ~/.profile

  or pass it inline:

    NIAGARA_REMOTE=https://github.com/USER/REPO.git ~/sun4v/update.sh
EOF
    exit 1
fi

command -v git >/dev/null || die "git not installed"

# The shipped tree may not be a git checkout at all -- during development it was
# delivered as a tarball over ssh. Convert it in place rather than failing, and keep
# the old copy, because it may contain local edits nobody wrote down.
if [[ ! -d "$PROJ/.git" ]]; then
    say "no git metadata in $PROJ -- converting to a clone of $REMOTE"
    (( CHECK )) && { say "(check mode: would clone and preserve the old tree)"; exit 0; }
    ts=$(date +%Y%m%d-%H%M%S)
    mv "$PROJ" "$PROJ.pre-git-$ts" || die "could not move $PROJ aside"
    git clone -q "$REMOTE" "$PROJ" || {
        mv "$PROJ.pre-git-$ts" "$PROJ"
        die "clone failed; original tree restored"
    }
    say "cloned; previous tree kept at $(basename "$PROJ.pre-git-$ts")"
    # A fresh clone has no build tree, so QEMU must be rebuilt.
    say "run ./setup-host.sh to rebuild qemu into the new tree"
    exit 0
fi

cd "$PROJ" || die "no $PROJ"

# Refuse to clobber local edits silently. This tree gets hand-patched during debugging.
if [[ -n "$(git status --porcelain)" ]]; then
    say "LOCAL CHANGES present:"
    git status --short | sed 's/^/      /'
    say "commit, stash, or discard them first -- refusing to overwrite"
    exit 1
fi

before=$(git rev-parse HEAD)
git fetch -q origin || die "fetch failed"
after=$(git rev-parse origin/HEAD 2>/dev/null || git rev-parse origin/master)

if [[ "$before" == "$after" ]]; then
    say "already current ($(git log --oneline -1))"
    exit 0
fi

say "updates available:"
git log --oneline "$before..$after" | head -20 | sed 's/^/      /'

# Did anything that affects the BUILD change? Only then is a rebuild warranted.
patch_changed=0
git diff --name-only "$before..$after" | grep -q '^patches/' && patch_changed=1

if (( CHECK )); then
    say "(check mode: nothing changed)"
    (( patch_changed )) && say "NOTE: patches/ changed -- a real run would need a qemu rebuild"
    exit 0
fi

git merge --ff-only "$after" > /dev/null 2>&1 || die "not a fast-forward; resolve by hand"
say "updated to $(git log --oneline -1)"

if (( patch_changed )); then
    say "patches/ changed -- QEMU MUST be rebuilt or you are running stale emulation:"
    say "    cd $PROJ && ./setup-host.sh"
else
    say "no patch changes; the existing qemu build is still correct"
fi

# Re-deploy the two host-side entry points, since they live outside the repo.
for f in playbox-run.sh:run.sh doctor.sh:doctor.sh update.sh:update.sh; do
    src="$PROJ/tools/${f%%:*}"; dst="$HOME/sun4v/${f##*:}"
    if [[ -f "$src" ]] && ! cmp -s "$src" "$dst"; then
        cp "$src" "$dst" && chmod +x "$dst" && say "refreshed $(basename "$dst")"
    fi
done

say "done. 'doctor.sh' is the quickest way to confirm nothing broke."
