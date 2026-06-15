#!/bin/sh
#
# test-restore-repo.sh - restore a test repository from its backup bundles.
#
# Usage: test-restore-repo.sh [<repo_name>] [<src_dir>] [<backup_dir>]
#
# Steps:
#   1. Locate the restore script and the backup directory.
#   2. Run backup-git-restore.sh from inside the backup directory.
#   3. Report pass/fail so the caller can tell backup vs. restore failures apart.
#

. "$(dirname "$0")/lib_test.sh"

# ── Arguments ─────────────────────────────────────────────────────────────────

REPO="${1:-${REPO_NAME}}"
GBACKUP_DIR="$(resolve_path "${2:-${GBACKUP_DIR}}")"
BACKUP_DIR="$(resolve_path "${3:-${BACKUP_DIR}}")"

# ── Step 1: Preconditions ─────────────────────────────────────────────────────

require_file "${GBACKUP_DIR}/backup-git-restore.sh" "restore script"
require_dir  "${BACKUP_DIR}"                        "backup dir '${BACKUP_DIR}'"

# ── Step 2: Run restore ───────────────────────────────────────────────────────

phase_restore "restoring '${REPO}' from bundles in '${BACKUP_DIR}'"

enter_dir "${BACKUP_DIR}"
"${GBACKUP_DIR}/backup-git-restore.sh" "${RESTORE_DIR}" "${REPO}"
rc=$?
leave_dir

# ── Step 3: Report ────────────────────────────────────────────────────────────

if [ "${rc}" -eq 0 ]; then
	phase_restore "OK — '${REPO}' restored to '${RESTORE_DIR}/${REPO}'"
else
	phase_restore "FAIL — restore exited with ${rc}"
	exit "${rc}"
fi
