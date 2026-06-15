#
# Shared helpers for the git-backup test suite.
#
# Sourced by run.sh and the test-*.sh step scripts. The caller is expected to
# have set SCRIPT_DIR to the directory of the test scripts before sourcing,
# e.g.:
#
#   SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
#   . "${SCRIPT_DIR}/lib-test.sh"
#
# Logging and precondition helpers (log_info / log_error / die / require_*)
# are reused from the production library so the tests speak the same language
# as the scripts under test.
#

. "${SCRIPT_DIR}/../src/lib-git-backup.sh"

# Where the scripts under test live.
GBACKUP_SRC_DIR="${SCRIPT_DIR}/../src"

# resolve_dir <path>
# Absolute path of <path> (the last component need not exist yet).
resolve_dir() {
	readlink -f "$1"
}
