#!/usr/bin/env bash
# Report what upstream has done since we forked.
#
# This replaces the bind-mount drift check that existed downstream before the
# fork. That script had to compare hashes of patched files against files inside
# a running container, because the patches were mounts and nothing tracked them.
# Now they are commits, so `git log` is the drift check.
#
# Read-only: fetches from upstream, touches no branch, builds nothing.
#
# Usage: ./check-upstream.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

FORK_POINT=v0.5.6
OURS=mochi
# Files we have modified. If upstream touches one of these, our commit needs
# re-deriving rather than just re-applying.
OUR_FILES=(
    betanin/notifications.py
    betanin/jobs/import_torrents.py
    betanin/config/betanin.py
    requirements-docker.txt
    Dockerfile
)

echo "==> Fetching upstream"
git fetch --quiet upstream --tags --prune

behind=$(git rev-list --count "$FORK_POINT..upstream/master")
echo
echo "Forked at $FORK_POINT. Upstream master is $behind commits ahead."

if (( behind == 0 )); then
    echo "Nothing to do."
    exit 0
fi

echo
echo "==> Upstream commits since $FORK_POINT"
git log --oneline --no-decorate "$FORK_POINT..upstream/master" | sed 's/^/    /'

echo
echo "==> New tags"
git tag --contains "$FORK_POINT" --sort=v:refname | grep -v "^$FORK_POINT$" | sed 's/^/    /' || echo "    none"

echo
echo "==> Do any of them touch files we have changed?"
hit=0
for f in "${OUR_FILES[@]}"; do
    n=$(git rev-list --count "$FORK_POINT..upstream/master" -- "$f")
    if (( n > 0 )); then
        printf '    %-40s %d upstream commit(s)  <-- re-derive ours\n' "$f" "$n"
        hit=1
    else
        printf '    %-40s unchanged upstream\n' "$f"
    fi
done

echo
if (( hit )); then
    echo "Some of our files moved upstream. Read docs/FORK.md before rebasing --"
    echo "a 0.6.x base is a real migration, not a bump, and the beets 2.x config"
    echo "changes there can fail silently."
else
    echo "None of our files moved upstream; a rebase would be mechanical."
fi
