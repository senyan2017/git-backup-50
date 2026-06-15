#!/bin/sh
#
# Restores a git repository from bundle files
# using backup-git-restore.sh.
#

REPO="${1:-"repoA"}"

GBACKUP_DIR="${2:-"../src"}"
BACKUP_DIR="${3:-"backups"}"

RESTORE_DIR="${4:-"/tmp/git"}"

GBACKUP_DIR="$(readlink -f "${GBACKUP_DIR}")"
BACKUP_DIR="$(readlink -f "${BACKUP_DIR}")"

if [ ! -f "${GBACKUP_DIR}/backup-git-restore.sh" ]; then
	echo "ERROR: ${GBACKUP_DIR}/backup-git-restore.sh does not exist!" >&2
	exit 1
fi

if [ ! -d "${BACKUP_DIR}" ]; then
	echo "ERROR: ${BACKUP_DIR} does not exist!" >&2
	exit 1
fi

"${GBACKUP_DIR}/backup-git-restore.sh" "${RESTORE_DIR}" "${REPO}" "${BACKUP_DIR}"
rc=$?

if [ ${rc} != 0 ]; then
	echo "ERROR: restore failed (exit code ${rc})" >&2
else
	echo "OK: restore succeeded"
fi

exit ${rc}
