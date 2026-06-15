#!/bin/sh
#
# lib.sh - shared utility functions for git-backup scripts.
#
# Source this file from other scripts:
#   . "$(dirname "$0")/lib.sh"
#
# Provides:
#   log_info / log_warn / log_error  - structured logging
#   die                              - print error and exit
#   resolve_path                     - canonicalise a path (readlink -f)
#   enter_dir / leave_dir            - safe cd with automatic return
#   require_file / require_dir       - precondition checks
#   bundle_verify                    - verify a git bundle file
#

# ── Logging ──────────────────────────────────────────────────────────────────

log_info() {
	echo "INFO: $*"
}

log_warn() {
	echo "WARN: $*"
}

log_error() {
	echo "ERROR: $*" >&2
}

# Print an error message and exit with the given code (default 1).
# Usage: die "something went wrong" [exit_code]
die() {
	_msg="$1"
	_code="${2:-1}"
	log_error "${_msg}"
	exit "${_code}"
}

# ── Path helpers ─────────────────────────────────────────────────────────────

# Resolve a path to its canonical absolute form.
resolve_path() {
	readlink -f "$1"
}

# ── Directory navigation ─────────────────────────────────────────────────────
#
# Pattern:
#   enter_dir /some/path   # pushes current dir, cd's into /some/path
#   ... do work ...
#   leave_dir              # pops back to the previous directory
#
# Only one level of nesting is needed in this codebase, so a single
# variable (_PREV_DIR) is sufficient.

_PREV_DIR=""

enter_dir() {
	_PREV_DIR="$(pwd)"
	cd "$1" || die "cannot enter directory: $1"
}

leave_dir() {
	if [ -n "${_PREV_DIR}" ]; then
		cd "${_PREV_DIR}"
		_PREV_DIR=""
	fi
}

# ── Precondition checks ───────────────────────────────────────────────────────

# Exit with an error unless the given path is an existing file.
require_file() {
	_path="$1"
	_label="${2:-$_path}"
	[ -f "${_path}" ] || die "${_label} does not exist or is not a file"
}

# Exit with an error unless the given path is an existing directory.
require_dir() {
	_path="$1"
	_label="${2:-$_path}"
	[ -d "${_path}" ] || die "${_label} does not exist or is not a directory"
}

# ── Git bundle helpers ────────────────────────────────────────────────────────

# Verify a bundle file; returns the git exit code (0 = ok).
bundle_verify() {
	_bundleFile="$1"
	git bundle verify "${_bundleFile}"
}

# Tag constants shared by backup and restore.
BACKUP_TAG="lastBackup"
