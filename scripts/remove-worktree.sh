#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────
MAIN_REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORKTREE_PARENT="${WORKTREE_PARENT:-$(dirname "$MAIN_REPO")}"
WORKTREE_DIR_NAME="rpg-battle-ai.worktrees"
WORKTREE_BASE="${WORKTREE_PARENT}/${WORKTREE_DIR_NAME}"

# ── Usage ───────────────────────────────────────────────────────
usage() {
    cat <<'USAGE'
Usage: remove-worktree.sh <worktree-name> [--delete-branch]

  worktree-name   Directory name under the worktrees folder (e.g., alpha-a5, fix-pathfinding)
  --delete-branch Also delete the local feature branch (default: keep it)

Examples:
  ./scripts/remove-worktree.sh alpha-a5
  ./scripts/remove-worktree.sh alpha-a5 --delete-branch
USAGE
    exit 1
}

# ── Argument parsing ────────────────────────────────────────────
WORKTREE_NAME="${1:-}"
DELETE_BRANCH=false

if [[ -z "$WORKTREE_NAME" ]]; then
    usage
fi

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --delete-branch) DELETE_BRANCH=true; shift ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

WORKTREE_PATH="${WORKTREE_BASE}/${WORKTREE_NAME}"

# ── Validate ────────────────────────────────────────────────────
if [[ ! -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree not found: ${WORKTREE_PATH}"
    echo ""
    echo "Available worktrees:"
    if [[ -d "$WORKTREE_BASE" ]]; then
        ls "$WORKTREE_BASE" 2>/dev/null || echo "  (none)"
    else
        echo "  (no worktrees directory)"
    fi
    exit 1
fi

# ── Detect branch name ─────────────────────────────────────────
BRANCH_NAME=""
BRANCH_NAME="$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

# ── Check for uncommitted changes ──────────────────────────────
if ! git -C "$WORKTREE_PATH" diff --quiet 2>/dev/null || \
   ! git -C "$WORKTREE_PATH" diff --cached --quiet 2>/dev/null; then
    echo "WARNING: Worktree has uncommitted changes!"
    echo ""
    git -C "$WORKTREE_PATH" status --short
    echo ""
    read -r -p "Proceed anyway? [y/N] " confirm
    if [[ "$confirm" != [yY] ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# ── Remove worktree ─────────────────────────────────────────────
echo "Removing worktree: ${WORKTREE_PATH}"
git -C "$MAIN_REPO" worktree remove "$WORKTREE_PATH" --force

# ── Optionally delete branch ────────────────────────────────────
if [[ "$DELETE_BRANCH" == true && -n "$BRANCH_NAME" ]]; then
    echo "Deleting branch: ${BRANCH_NAME}"
    git -C "$MAIN_REPO" branch -d "$BRANCH_NAME" 2>/dev/null || \
        git -C "$MAIN_REPO" branch -D "$BRANCH_NAME"
fi

# ── Clean up empty parent ───────────────────────────────────────
if [[ -d "$WORKTREE_BASE" ]] && [[ -z "$(ls -A "$WORKTREE_BASE" 2>/dev/null)" ]]; then
    rmdir "$WORKTREE_BASE"
    echo "Removed empty worktrees directory."
fi

echo ""
echo "Done."
if [[ -n "$BRANCH_NAME" ]]; then
    if [[ "$DELETE_BRANCH" == true ]]; then
        echo "  Branch '${BRANCH_NAME}' deleted."
    else
        echo "  Branch '${BRANCH_NAME}' still exists. Delete later with:"
        echo "    git branch -d ${BRANCH_NAME}"
    fi
fi
