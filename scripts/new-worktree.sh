#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────
MAIN_REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORKTREE_PARENT="${WORKTREE_PARENT:-$(dirname "$MAIN_REPO")}"
WORKTREE_DIR_NAME="rpg-battle-ai.worktrees"
WORKTREE_BASE="${WORKTREE_PARENT}/${WORKTREE_DIR_NAME}"
BASE_BRANCH="${BASE_BRANCH:-development}"

# ── Usage ───────────────────────────────────────────────────────
usage() {
    cat <<'USAGE'
Usage: new-worktree.sh <task-id> [description]

  task-id      An alpha phase (a5, a6, a8...) or a kebab-case slug (fix-pathfinding)
  description  Required for ad-hoc tasks; ignored for alpha phases (pulled from spec)

Environment:
  WORKTREE_PARENT  Parent directory for the worktrees folder (default: ../)
  BASE_BRANCH      Branch to fork from (default: development)

Examples:
  ./scripts/new-worktree.sh a5
  ./scripts/new-worktree.sh fix-pathfinding "Fix A* pathfinder edge case with elevation 0"
USAGE
    exit 1
}

# ── Argument parsing ────────────────────────────────────────────
TASK_ID="${1:-}"
DESCRIPTION="${2:-}"

if [[ -z "$TASK_ID" ]]; then
    usage
fi

# ── Detect task type ────────────────────────────────────────────
ALPHA_REGEX='^[aA]([0-9]+)$'
IS_ALPHA=false
PHASE_NUM=""

if [[ "$TASK_ID" =~ $ALPHA_REGEX ]]; then
    IS_ALPHA=true
    PHASE_NUM="${BASH_REMATCH[1]}"
    TASK_ID_LOWER="a${PHASE_NUM}"
    TASK_ID_UPPER="A${PHASE_NUM}"
    BRANCH_NAME="feature/alpha-${TASK_ID_LOWER}"
    WORKTREE_NAME="alpha-${TASK_ID_LOWER}"
else
    if [[ -z "$DESCRIPTION" ]]; then
        echo "Error: Ad-hoc tasks require a description as the second argument."
        echo ""
        usage
    fi
    SLUG="$(echo "$TASK_ID" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | tr -cd 'a-z0-9-')"
    BRANCH_NAME="feature/${SLUG}"
    WORKTREE_NAME="${SLUG}"
fi

WORKTREE_PATH="${WORKTREE_BASE}/${WORKTREE_NAME}"

# ── Validate preconditions ──────────────────────────────────────
if [[ ! -d "${MAIN_REPO}/.git" && ! -f "${MAIN_REPO}/.git" ]]; then
    echo "Error: ${MAIN_REPO} is not a git repository."
    exit 1
fi

if ! git -C "$MAIN_REPO" rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
    echo "Error: Base branch '${BASE_BRANCH}' does not exist."
    exit 1
fi

if git -C "$MAIN_REPO" rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
    echo "Error: Branch '${BRANCH_NAME}' already exists."
    echo "  To reuse it, remove the existing worktree first:"
    echo "    ./scripts/remove-worktree.sh ${WORKTREE_NAME}"
    exit 1
fi

if [[ -d "$WORKTREE_PATH" ]]; then
    echo "Error: Worktree directory already exists: ${WORKTREE_PATH}"
    exit 1
fi

SPEC_FILE=""
IMPL_FILE=""
if [[ "$IS_ALPHA" == true ]]; then
    SPEC_FILE="docs/alpha-phaseA${PHASE_NUM}-spec.md"
    IMPL_FILE="docs/alpha-phaseA${PHASE_NUM}-implementation-plan.md"
    if [[ ! -f "${MAIN_REPO}/${SPEC_FILE}" ]]; then
        echo "Error: Spec file not found: ${SPEC_FILE}"
        exit 1
    fi
fi

# ── Create worktree ─────────────────────────────────────────────
echo "Creating worktree..."
mkdir -p "$WORKTREE_BASE"
git -C "$MAIN_REPO" worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_BRANCH"
echo "  Branch: ${BRANCH_NAME}"
echo "  Path:   ${WORKTREE_PATH}"

# ── Copy .claude/ config ────────────────────────────────────────
if [[ -d "${MAIN_REPO}/.claude" ]]; then
    echo "Copying .claude/ config..."
    cp -r "${MAIN_REPO}/.claude" "${WORKTREE_PATH}/.claude"
fi

# ── Generate CLAUDE.local.md ────────────────────────────────────
echo "Generating CLAUDE.local.md..."

generate_alpha_context() {
    local spec_path="${MAIN_REPO}/${SPEC_FILE}"

    # Extract title from line 1: "# Phase A5 — Battle Bands & Save System Specification"
    local title
    title="$(head -1 "$spec_path" | sed 's/^# //' | sed 's/ Specification$//')"

    # Extract "Builds on" lines
    local builds_on
    builds_on="$(grep '^\*\*Builds on' "$spec_path" || echo "(none found)")"

    # Check implementation plan
    local impl_note=""
    if [[ -f "${MAIN_REPO}/${IMPL_FILE}" ]]; then
        impl_note="- Implementation plan: \`${IMPL_FILE}\`"
    else
        impl_note="- Implementation plan: not yet written"
    fi

    cat > "${WORKTREE_PATH}/CLAUDE.local.md" <<LOCALEOF
# Active Task: ${title}

## Branch

\`${BRANCH_NAME}\` (merge target: \`${BASE_BRANCH}\`)

## Specification

- Spec: \`${SPEC_FILE}\`
${impl_note}

## Dependencies

${builds_on}

## Scope

You are implementing **Phase ${TASK_ID_UPPER}** only. Do not modify systems outside this phase's scope unless the spec explicitly calls for it. When in doubt, check the spec's "In scope" and "Out of scope" sections.

Read the spec and implementation plan before starting work. Follow the exit criteria as your definition of done.

## Key References

- Master alpha spec: \`docs/alpha-specs.md\`
- Alpha roadmap: \`docs/alpha-implementation-plan.md\`
- Phase progress in CLAUDE.md: check the "Alpha (in progress)" section for what is already built
LOCALEOF
}

generate_adhoc_context() {
    cat > "${WORKTREE_PATH}/CLAUDE.local.md" <<LOCALEOF
# Active Task: ${TASK_ID}

## Description

${DESCRIPTION}

## Branch

\`${BRANCH_NAME}\` (merge target: \`${BASE_BRANCH}\`)

## Scope

This is an ad-hoc task. Stay focused on the described objective. Avoid unrelated refactors or scope creep.
LOCALEOF
}

if [[ "$IS_ALPHA" == true ]]; then
    generate_alpha_context
else
    generate_adhoc_context
fi

# ── Print next steps ────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Worktree ready: ${WORKTREE_PATH}"
echo "  Branch:         ${BRANCH_NAME}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. cd \"${WORKTREE_PATH}\""
echo "  2. Launch Claude Code in this directory"
echo "     Claude will read CLAUDE.md (project) + CLAUDE.local.md (task context)"
if [[ "$IS_ALPHA" == true ]]; then
    echo "  3. Tell Claude: \"Implement Phase ${TASK_ID_UPPER} per the spec.\""
else
    echo "  3. Tell Claude: \"${DESCRIPTION}\""
fi
echo "  4. When done, push and create a PR to '${BASE_BRANCH}', then clean up:"
echo "     ./scripts/remove-worktree.sh ${WORKTREE_NAME}"
echo ""
