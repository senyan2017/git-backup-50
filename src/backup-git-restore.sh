#!/bin/sh
#
# Restore a single git repository from multiple bundle files.
#
# Run this script inside a directory with backup bundle files.
#
# Usage: backup-git-restore.sh <restore_dir> <repo_name>
# Restores the repository <repo_name> from bundle files named "<repo_name>_*.bundle"
# into a new git repository "<restore_dir>/<repo_name>".
#

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/lib-git-backup.sh"

# restore_initial <bundle_file> <display_name>
# No repository yet: verify the (full) bundle and clone a fresh repository.
restore_initial() {
	bundleFile=$1
	file=$2

	log_info "verifying bundle '${file}' for '${REPO}'"
	run_or_die "verification failed" git bundle verify "${bundleFile}"

	log_info "restoring repo ${REPO} from bundle '${file}'..."
	run_or_die "clone failed" git clone "${bundleFile}" "${REPO_DIR}"
}

# restore_incremental <bundle_file> <display_name>
# Repository exists: verify the bundle against it and pull the new commits in.
restore_incremental() {
	bundleFile=$1
	file=$2

	cd "${REPO_DIR}" || die "cannot enter ${REPO_DIR}"

	log_info "verifying bundle '${file}' for '${REPO}'"
	run_or_die "verification failed" git bundle verify "${bundleFile}"

	log_info "pulling from bundle '${file}'..."
	run_or_die "pull failed" git pull "${bundleFile}"

	cd "${backupDir}" || die "cannot return to ${backupDir}"
}

if [ $# -ne 2 ]; then
	echo "Usage: $(basename "$0") <restore_dir> <repo_name>"
	echo "Example: $(basename "$0") /tmp/git/ repo"
	exit 1
fi

RESTORE_DIR=$1
REPO=$2
REPO_DIR="${RESTORE_DIR}/${REPO}"

backupDir=$(pwd)
rc=1

# Apply the bundles in order: the first one seeds the repository (clone),
# every following one is pulled into it.
for file in `ls ${REPO}_*.bundle`
do
	bundleFile="${backupDir}/${file}"

	if [ -d "${REPO_DIR}" ]; then
		restore_incremental "${bundleFile}" "${file}"
	else
		restore_initial "${bundleFile}" "${file}"
	fi

	rc=0
done

if [ "${rc}" -eq 0 ]; then
	log_info "repository ${REPO} restored successfully"
else
	die_rc "${rc}" "restoring failed"
fi
