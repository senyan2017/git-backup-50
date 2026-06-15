#
# Shared helpers for the git-backup scripts.
#
# This file is meant to be sourced, not executed:
#   . "$(dirname "$0")/lib-git-backup.sh"
#
# It collects the shell patterns that used to be copy-pasted across
# backup-git.sh and backup-git-restore.sh: logging, error handling and
# simple filesystem precondition checks.
#

# --- logging -----------------------------------------------------------------

log_info() {
	echo "INFO: $*"
}

log_error() {
	echo "ERROR: $*" >&2
}

# --- error handling ----------------------------------------------------------

# die <message>
# Log an error and exit with status 1.
die() {
	log_error "$*"
	exit 1
}

# die_rc <rc> <message>
# Log "<message>: <rc>" and exit preserving the given return code.
die_rc() {
	rc=$1
	shift
	log_error "$*: ${rc}"
	exit "${rc}"
}

# run_or_die <error-message> <command> [args...]
# Run a command and, on failure, exit preserving its return code.
# Mirrors the "rc=$?; if [ $rc != 0 ]; then echo ERROR; exit $rc; fi" blocks
# that were repeated throughout the restore script.
run_or_die() {
	errmsg=$1
	shift
	"$@"
	rc=$?
	if [ "${rc}" -ne 0 ]; then
		die_rc "${rc}" "${errmsg}"
	fi
	return 0
}

# --- filesystem preconditions ------------------------------------------------

# require_dir <path> [message]
require_dir() {
	[ -d "$1" ] || die "${2:-$1 is not a directory}"
}

# require_file <path> [message]
require_file() {
	[ -f "$1" ] || die "${2:-$1 does not exist!}"
}
