#!/bin/sh
#
# run.sh - end-to-end test for the git backup / restore pipeline.
#
# Phases:
#   1. Setup   — prepare working directories.
#   2. Backup  — clone a seed repo, add 10 incremental commits,
#                and create a bundle after each one.
#   3. Restore — replay all bundles into a fresh directory.
#   4. Verify  — check that the restored repo looks correct.
#   5. Cleanup — remove temporary artefacts.
#
# Usage:  cd test && ./run.sh
#

. "$(dirname "$0")/lib_test.sh"

TEST_BACKUP_DIR="backups"
WORK_REPO="${REPO_NAME}"           # local working repo (created by test-fill-repo.sh)
RESTORE_TARGET="/tmp/git"          # where test-restore-repo.sh puts the restored copy
RESTORED_REPO="${RESTORE_TARGET}/${REPO_NAME}"
NUM_COMMITS=10

# Make paths absolute so cleanup works regardless of cwd.
BACKUP_DIR="$(resolve_path "${TEST_BACKUP_DIR}")"

# ── Phase 1: Setup ────────────────────────────────────────────────────────────

phase_test "setup — cleaning leftovers from previous runs"
cleanup_dirs "${TEST_BACKUP_DIR}" "${WORK_REPO}" "${RESTORE_TARGET}"
mkdir -p "${TEST_BACKUP_DIR}"

# ── Phase 2: Backup — create commits and bundles ─────────────────────────────

phase_backup "creating ${NUM_COMMITS} incremental commits + bundles"

i=1
while [ "${i}" -le "${NUM_COMMITS}" ]; do
	phase_backup "commit ${i}/${NUM_COMMITS}"
	./test-fill-repo.sh "${TEST_BUNDLE}" "${WORK_REPO}" "${GBACKUP_DIR}" "${TEST_BACKUP_DIR}"
	assert_exit_ok "backup round ${i}" $?
	sleep 1
	i=$((i + 1))
done

phase_backup "all ${NUM_COMMITS} backup rounds completed"

# Quick sanity check: we should have at least one bundle file.
bundleCount="$(ls "${TEST_BACKUP_DIR}/${REPO_NAME}_"*.bundle 2>/dev/null | wc -l)"
if [ "${bundleCount}" -eq 0 ]; then
	die "[FAIL] no bundle files found in '${TEST_BACKUP_DIR}' — backup pipeline is broken"
fi
phase_backup "found ${bundleCount} bundle file(s) in '${TEST_BACKUP_DIR}'"

# ── Phase 3: Restore ──────────────────────────────────────────────────────────

phase_restore "replaying bundles into '${RESTORED_REPO}'"
./test-restore-repo.sh "${REPO_NAME}" "${GBACKUP_DIR}" "${TEST_BACKUP_DIR}"
assert_exit_ok "restore pipeline" $?

# ── Phase 4: Verify ──────────────────────────────────────────────────────────

phase_test "verifying restored repository"
assert_dir_exists "${RESTORED_REPO}" "restored repo '${RESTORED_REPO}'"

# The restored repo should have at least NUM_COMMITS commits on master.
commitCount="$(git -C "${RESTORED_REPO}" rev-list --count master)"
phase_test "restored master has ${commitCount} commit(s)"

if [ "${commitCount}" -lt "${NUM_COMMITS}" ]; then
	die "[FAIL] expected at least ${NUM_COMMITS} commits, got ${commitCount}"
fi
log_info "[PASS] commit count check (>= ${NUM_COMMITS})"

# ── Phase 5: Cleanup ─────────────────────────────────────────────────────────

phase_test "cleanup"
cleanup_dirs "${TEST_BACKUP_DIR}" "${WORK_REPO}" "${RESTORE_TARGET}"

echo ""
echo "=== ALL TESTS PASSED ==="
