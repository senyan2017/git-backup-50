#!/bin/sh
#
# One iteration of the backup chain test:
#   1. make sure a working repository exists (cloned from repo.bundle),
#   2. simulate a change and commit it,
#   3. create an incremental backup bundle using backup-git.sh.
#

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/lib-test.sh"

SRC_BUNDLE=${1:-"repo.bundle"}
REPO=${2:-"repoA"}
GBACKUP_DIR=$(resolve_dir "${3:-../src}")
BACKUP_DIR=$(resolve_dir "${4:-backups}")

# ensure_clone: clone the working repository from the seed bundle once.
ensure_clone() {
	[ -d "${REPO}" ] || git clone "${SRC_BUNDLE}" "${REPO}"
}

# simulate_commit: produce one dummy change and commit it.
simulate_commit() {
	(
		cd "${REPO}" || exit 1
		echo "AAA" >> A
		git commit -am "changes $(date +%Y%m%d-%H%M%S)"
	)
}

require_file "${GBACKUP_DIR}/backup-git.sh"
[ -d "${BACKUP_DIR}" ] || mkdir "${BACKUP_DIR}"

ensure_clone
simulate_commit

# Run the backup under test.
"${GBACKUP_DIR}/backup-git.sh" "${REPO}" "${BACKUP_DIR}"
