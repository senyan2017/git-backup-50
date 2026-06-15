#!/bin/sh
#
# test/lib_test.sh - shared helpers for the test suite.
#
# Source from test scripts:
#   . "$(dirname "$0")/lib_test.sh"
#
# Depends on src/lib.sh (sourced automatically).
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Pull in the project-wide library.
. "${SCRIPT_DIR}/../src/lib.sh"

# ── Default paths ─────────────────────────────────────────────────────────────
# These can be overridden by individual test scripts before sourcing this file,
# but sensible defaults are provided here.

GBACKUP_DIR="${GBACKUP_DIR:-$(resolve_path "${SCRIPT_DIR}/../src")}"
BACKUP_DIR="${BACKUP_DIR:-$(resolve_path "${SCRIPT_DIR}/backups")}"

TEST_BUNDLE="${TEST_BUNDLE:-repo.bundle}"
REPO_NAME="${REPO_NAME:-repoA}"
RESTORE_DIR="${RESTORE_DIR:-/tmp/git}"

# ── Test-phase logging ────────────────────────────────────────────────────────
# Use these to make it obvious which phase a message belongs to.

phase_backup() {
	echo "--- [BACKUP] $*"
}

phase_restore() {
	echo "--- [RESTORE] $*"
}

phase_test() {
	echo "--- [TEST] $*"
}

# ── Assertions ────────────────────────────────────────────────────────────────

assert_exit_ok() {
	_label="$1"
	_rc="$2"
	if [ "${_rc}" -ne 0 ]; then
		die "[FAIL] ${_label} (exit code ${_rc})"
	fi
	log_info "[PASS] ${_label}"
}

assert_dir_exists() {
	_path="$1"
	_label="${2:-directory '${_path}'}"
	[ -d "${_path}" ] || die "[FAIL] expected ${_label} to exist"
	log_info "[PASS] ${_label} exists"
}

assert_file_exists() {
	_path="$1"
	_label="${2:-file '${_path}'}"
	[ -f "${_path}" ] || die "[FAIL] expected ${_label} to exist"
	log_info "[PASS] ${_label} exists"
}

# ── Cleanup helper ────────────────────────────────────────────────────────────

cleanup_dirs() {
	for _d in "$@"; do
		[ -d "${_d}" ] && rm -rf "${_d}"
	done
}
