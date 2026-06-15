#!/bin/sh
#
# Restore chain test: rebuild a repository from the bundle files produced by
# the backup chain, using backup-git-restore.sh. The restored repository lands
# in /tmp/git/. Exits non-zero if the restore fails.
#

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/lib-test.sh"

REPO=${1:-"repoA"}
GBACKUP_DIR=$(resolve_dir "${2:-../src}")
BACKUP_DIR=$(resolve_dir "${3:-backups}")
RESTORE_DIR="/tmp/git"

require_file "${GBACKUP_DIR}/backup-git-restore.sh"
require_dir "${BACKUP_DIR}" "${BACKUP_DIR} does not exist!"

# The restore script expects to run from the directory holding the bundles;
# the subshell keeps that cd local and lets us capture its real exit code.
(
	cd "${BACKUP_DIR}" || exit 1
	"${GBACKUP_DIR}/backup-git-restore.sh" "${RESTORE_DIR}" "${REPO}"
)
rc=$?

if [ "${rc}" != 0 ]; then
	echo "ERROR"
else
	echo "OK"
fi

exit "${rc}"
