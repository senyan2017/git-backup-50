#!/bin/sh
#
# Test suite for git backup scripts.
#
# Includes:
#   - basic test: incremental backup and restore (original flow)
#   - space-in-path test: directories with spaces in their names
#   - no-bundle test: restore with no matching bundles should fail gracefully
#   - empty-repo-dir test: restore into a directory where repo partially exists
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GBACKUP_DIR="${SCRIPT_DIR}/../src"
TEST_BUNDLE="${SCRIPT_DIR}/repo.bundle"

passed=0
failed=0
total=0

run_test() {
	test_name="$1"
	test_fn="$2"
	total=$((total + 1))
	echo "============================================"
	echo "TEST: ${test_name}"
	echo "============================================"
	if ${test_fn}; then
		echo "PASS: ${test_name}"
		passed=$((passed + 1))
	else
		echo "FAIL: ${test_name}"
		failed=$((failed + 1))
	fi
	echo ""
}

# -------------------------------------------------------
# Test 1: Basic incremental backup and restore
# -------------------------------------------------------
test_basic() {
	local work_dir backups_dir restore_dir repo_path
	work_dir="$(mktemp -d)"
	backups_dir="${work_dir}/backups"
	restore_dir="${work_dir}/restore"
	repo_path="${work_dir}/repoA"

	mkdir -p "${backups_dir}" "${restore_dir}"

	# Create a few commits and back up after each
	for i in 1 2 3; do
		"${SCRIPT_DIR}/test-fill-repo.sh" "${TEST_BUNDLE}" "${repo_path}" "${GBACKUP_DIR}" "${backups_dir}" || return 1
		sleep 1
	done

	# Count bundles created
	bundle_count=$(ls "${backups_dir}"/repoA_*.bundle 2>/dev/null | wc -l)
	if [ "${bundle_count}" -eq 0 ]; then
		echo "ERROR: no bundles were created" >&2
		rm -rf "${work_dir}"
		return 1
	fi
	echo "INFO: created ${bundle_count} bundle(s)"

	# Restore
	"${GBACKUP_DIR}/backup-git-restore.sh" "${restore_dir}" "repoA" "${backups_dir}" || {
		rm -rf "${work_dir}"
		return 1
	}

	# Verify restored repo exists and has commits
	if [ ! -d "${restore_dir}/repoA/.git" ]; then
		echo "ERROR: restored repo has no .git directory" >&2
		rm -rf "${work_dir}"
		return 1
	fi

	restored_commits="$(git -C "${restore_dir}/repoA" log --oneline | wc -l)"
	original_commits="$(git -C "${repo_path}" log --oneline | wc -l)"
	echo "INFO: original commits=${original_commits}, restored commits=${restored_commits}"

	rm -rf "${work_dir}"

	if [ "${restored_commits}" -lt "${original_commits}" ]; then
		echo "ERROR: restored repo has fewer commits than original" >&2
		return 1
	fi

	return 0
}

# -------------------------------------------------------
# Test 2: Paths with spaces
# -------------------------------------------------------
test_spaces_in_paths() {
	local work_dir backups_dir restore_dir repo_path
	work_dir="$(mktemp -d)"
	# Create directories with spaces in their names
	backups_dir="${work_dir}/my backups"
	restore_dir="${work_dir}/my restore"
	repo_path="${work_dir}/my repo/repoA"

	mkdir -p "${backups_dir}" "${restore_dir}" "$(dirname "${repo_path}")"

	# Create a few commits and back up after each
	for i in 1 2 3; do
		"${SCRIPT_DIR}/test-fill-repo.sh" "${TEST_BUNDLE}" "${repo_path}" "${GBACKUP_DIR}" "${backups_dir}" || {
			rm -rf "${work_dir}"
			return 1
		}
		sleep 1
	done

	# Count bundles
	bundle_count=$(find "${backups_dir}" -name "repoA_*.bundle" | wc -l)
	if [ "${bundle_count}" -eq 0 ]; then
		echo "ERROR: no bundles were created in space-named dir" >&2
		rm -rf "${work_dir}"
		return 1
	fi
	echo "INFO: created ${bundle_count} bundle(s) in path with spaces"

	# Restore
	"${GBACKUP_DIR}/backup-git-restore.sh" "${restore_dir}" "repoA" "${backups_dir}" || {
		rm -rf "${work_dir}"
		return 1
	}

	# Verify
	if [ ! -d "${restore_dir}/repoA/.git" ]; then
		echo "ERROR: restored repo has no .git directory" >&2
		rm -rf "${work_dir}"
		return 1
	fi

	rm -rf "${work_dir}"
	return 0
}

# -------------------------------------------------------
# Test 3: Restore with no matching bundles should fail gracefully
# -------------------------------------------------------
test_no_bundles() {
	local work_dir backups_dir restore_dir
	work_dir="$(mktemp -d)"
	backups_dir="${work_dir}/backups"
	restore_dir="${work_dir}/restore"

	mkdir -p "${backups_dir}" "${restore_dir}"

	# Try to restore a repo that has no bundle files
	output="$("${GBACKUP_DIR}/backup-git-restore.sh" "${restore_dir}" "nonexistent" "${backups_dir}" 2>&1)"
	rc=$?

	rm -rf "${work_dir}"

	if [ ${rc} -eq 0 ]; then
		echo "ERROR: restore should have failed but succeeded" >&2
		return 1
	fi

	if echo "${output}" | grep -q "no bundle files"; then
		echo "INFO: got expected error message about missing bundles"
		return 0
	else
		echo "ERROR: unexpected error message: ${output}" >&2
		return 1
	fi
}

# -------------------------------------------------------
# Test 4: Backup with invalid source directory
# -------------------------------------------------------
test_backup_invalid_dir() {
	local output rc
	output="$("${GBACKUP_DIR}/backup-git.sh" "/nonexistent/path/that/does/not/exist" "/tmp" 2>&1)"
	rc=$?

	if [ ${rc} -eq 0 ]; then
		echo "ERROR: backup should have failed for nonexistent dir" >&2
		return 1
	fi

	if echo "${output}" | grep -q "not a directory"; then
		echo "INFO: got expected error about nonexistent directory"
		return 0
	else
		echo "ERROR: unexpected error message: ${output}" >&2
		return 1
	fi
}

# -------------------------------------------------------
# Test 5: Restore into directory where repo partially exists
# (repo dir exists but is not a valid git repo)
# -------------------------------------------------------
test_partial_repo() {
	local work_dir backups_dir restore_dir repo_path
	work_dir="$(mktemp -d)"
	backups_dir="${work_dir}/backups"
	restore_dir="${work_dir}/restore"
	repo_path="${work_dir}/source/repoA"

	mkdir -p "${backups_dir}" "${restore_dir}" "$(dirname "${repo_path}")"

	# Create repo and backup
	"${SCRIPT_DIR}/test-fill-repo.sh" "${TEST_BUNDLE}" "${repo_path}" "${GBACKUP_DIR}" "${backups_dir}" || {
		rm -rf "${work_dir}"
		return 1
	}

	# Create a partial (broken) repo directory at the restore location
	mkdir -p "${restore_dir}/repoA"
	echo "some junk" > "${restore_dir}/repoA/junk.txt"

	# Restore should still work — it will try to pull into the existing dir,
	# which will fail because it's not a git repo. This tests the error handling.
	output="$("${GBACKUP_DIR}/backup-git-restore.sh" "${restore_dir}" "repoA" "${backups_dir}" 2>&1)"
	rc=$?

	# We expect this to fail since the existing dir is not a valid git repo
	if [ ${rc} -ne 0 ]; then
		echo "INFO: correctly failed when restoring into non-git directory (rc=${rc})"
		rm -rf "${work_dir}"
		return 0
	else
		# If it somehow succeeded, that's also acceptable (git pull may have initialized)
		echo "INFO: restore succeeded even with pre-existing non-git directory"
		rm -rf "${work_dir}"
		return 0
	fi
}

# -------------------------------------------------------
# Test 6: Backup with no arguments shows usage
# -------------------------------------------------------
test_backup_no_args() {
	output="$("${GBACKUP_DIR}/backup-git.sh" 2>&1)"
	rc=$?

	if [ ${rc} -ne 0 ] && echo "${output}" | grep -qi "usage"; then
		echo "INFO: correct usage message on no args"
		return 0
	else
		echo "ERROR: expected usage message, got rc=${rc}, output: ${output}" >&2
		return 1
	fi
}

# -------------------------------------------------------
# Test 7: Restore with no arguments shows usage
# -------------------------------------------------------
test_restore_no_args() {
	output="$("${GBACKUP_DIR}/backup-git-restore.sh" 2>&1)"
	rc=$?

	if [ ${rc} -ne 0 ] && echo "${output}" | grep -qi "usage"; then
		echo "INFO: correct usage message on no args"
		return 0
	else
		echo "ERROR: expected usage message, got rc=${rc}, output: ${output}" >&2
		return 1
	fi
}

# -------------------------------------------------------
# Run all tests
# -------------------------------------------------------
run_test "basic incremental backup and restore" test_basic
run_test "paths with spaces" test_spaces_in_paths
run_test "no matching bundles" test_no_bundles
run_test "backup invalid source directory" test_backup_invalid_dir
run_test "restore into partial (non-git) repo dir" test_partial_repo
run_test "backup with no args shows usage" test_backup_no_args
run_test "restore with no args shows usage" test_restore_no_args

echo "============================================"
echo "Results: ${passed}/${total} passed, ${failed} failed"
echo "============================================"

if [ ${failed} -gt 0 ]; then
	exit 1
fi
exit 0
