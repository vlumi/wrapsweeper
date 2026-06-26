#!/usr/bin/env bash
# Bump the shared build number (CURRENT_PROJECT_VERSION) for BOTH app targets in
# project.yml, in lock-step, then optionally open a PR.
#
# The build number is shared across iOS + macOS (one number for both apps). This
# sets both targets to max(current) + 1 — so a one-off divergence still resolves
# upward, and you never have to hand-edit two places or remember which is higher.
#
# Usage:
#   Scripts/bump-build.sh            # bump both + branch + commit + PR (default)
#   Scripts/bump-build.sh --no-pr    # bump + commit on a branch, no PR (push yourself)
#   Scripts/bump-build.sh --local    # just edit project.yml (no branch/commit/PR)
#   Scripts/bump-build.sh --set N    # set both to exactly N (e.g. to match an ASC build)
set -euo pipefail

cd "$(dirname "$0")/.."

mode="pr"        # pr | no-pr | local
explicit=""      # exact value for --set

while [ $# -gt 0 ]; do
    case "$1" in
        --no-pr) mode="no-pr" ;;
        --local) mode="local" ;;
        --set) shift; explicit="${1:?--set needs a number}" ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
done

file="project.yml"

# All current CURRENT_PROJECT_VERSION values (quoted ints). Read into an array
# without `mapfile` — macOS ships Bash 3.2, which doesn't have it.
current=()
while IFS= read -r v; do
    current+=("$v")
done < <(grep -oE 'CURRENT_PROJECT_VERSION: *"[0-9]+"' "$file" | grep -oE '[0-9]+')

if [ "${#current[@]}" -eq 0 ]; then
    echo "error: no CURRENT_PROJECT_VERSION found in $file" >&2
    exit 1
fi

# Determine the next value: explicit (--set) or max(current) + 1.
if [ -n "$explicit" ]; then
    if ! [[ "$explicit" =~ ^[0-9]+$ ]]; then
        echo "error: --set value must be a non-negative integer" >&2
        exit 2
    fi
    next="$explicit"
else
    max=0
    for v in "${current[@]}"; do (( v > max )) && max="$v"; done
    next=$(( max + 1 ))
fi

old_list=$(IFS=,; echo "${current[*]}")
echo "build number: [$old_list] → $next (both targets)"

# Rewrite every CURRENT_PROJECT_VERSION line to the new value. The value is always
# quoted, so this is unambiguous; both app targets are updated in one pass.
#   macOS sed needs the '' after -i; this is a macOS-only project.
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: *)\"[0-9]+\"/\1\"${next}\"/" "$file"

# Sanity: confirm both now read `next`.
if [ "$(grep -cE "CURRENT_PROJECT_VERSION: *\"${next}\"" "$file")" -ne "${#current[@]}" ]; then
    echo "error: not all targets updated to ${next} — check $file" >&2
    exit 1
fi

if [ "$mode" = "local" ]; then
    echo "done (project.yml edited; not committed)."
    exit 0
fi

# Branch + commit.
branch="chore/bump-build-${next}"
if git rev-parse --verify "$branch" >/dev/null 2>&1; then
    echo "error: branch '$branch' already exists" >&2
    exit 1
fi
git checkout -b "$branch" >/dev/null
git add "$file"
git commit --quiet -m "$(cat <<EOF
Bump build number to ${next} (iOS + macOS)

Shared build number for both app targets, bumped together by Scripts/bump-build.sh.
EOF
)"

if [ "$mode" = "no-pr" ]; then
    echo "committed on $branch (not pushed)."
    exit 0
fi

git push --quiet -u origin "$branch"
gh pr create \
    --title "Bump build number to ${next} (iOS + macOS)" \
    --body "Bumps the shared \`CURRENT_PROJECT_VERSION\` for both app targets to **${next}** via \`Scripts/bump-build.sh\` — for a fresh App Store Connect build." \
    --head "$branch"
echo "PR opened for build ${next}."
