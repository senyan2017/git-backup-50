#!/bin/sh
#
# Backup one (or more) git repositories using bundle files.
#
# Searches for git repositories inside the given directory
# and creates incremental bundle files containing the changes since last backup.
# The tag "lastBackup" is used to mark the last commit that was included in a bundle.
#
# Usage: backup-git.sh <repository_dir> [<backup_dir>]
# Creates bundle files for repositories found in <repository_dir> and saves them in <backup_dir>.
# Bundle filename pattern "<repository_name>_YYYYmmdd-HHMMSS.bundle"
#

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/lib-git-backup.sh"

BACKUP_TAG="lastBackup"

# find_repos <basedir>
# Emit the .git directory of every git repository found below <basedir>.
find_repos() {
	find "$1" -maxdepth 2 -type d -name '.git'
}

# backup_repo <git_dir> <backup_dir>
# Create an (incremental) bundle for a single repository and move the
# "lastBackup" tag forward. All git work happens in a subshell so the caller's
# working directory is never disturbed.
backup_repo() {
	gitDir=$1
	backupDir=$2

	repoName=$(basename "$(dirname "${gitDir}")")
	fileName="${backupDir}/${repoName}_$(date +%Y%m%d-%H%M%S).bundle"

	log_info "processing ${repoName}..."

	(
		cd "${gitDir}" || exit 1

		# Decide between a full and an incremental bundle.
		log_info "checking tag '${BACKUP_TAG}'"
		if [ "$(git tag | grep -c "${BACKUP_TAG}")" -eq 0 ]; then
			# No backup was ever made: create the initial, full bundle.
			log_info "exporting ${repoName} to ${fileName}"
			git bundle create "${fileName}" --all
		else
			# A previous backup exists: bundle only new commits, if any.
			if [ "$(git log "${BACKUP_TAG}..master" --oneline | wc -l)" -eq 0 ]; then
				log_info "no changes since last backup!"
				exit 0
			fi

			log_info "'${BACKUP_TAG}' tag:"
			git rev-parse "${BACKUP_TAG}^0"

			log_info "exporting '${repoName}' (${BACKUP_TAG}..master) to ${fileName}"
			git bundle create "${fileName}" --all "${BACKUP_TAG}..master"
		fi

		# Verify the freshly written bundle and remember this backup point.
		log_info "verifying bundle '${fileName}'"
		git bundle verify "${fileName}"

		log_info "creating tag '${BACKUP_TAG}'"
		git tag -f "${BACKUP_TAG}" master
	)
}

if [ $# -lt 1 ]; then
	echo "Usage: $0 <repository_dir> [<backup_dir>]"
	exit 0
fi

BACKUP_REPOS_BASEDIR=$1
BACKUP_DIR=${2:-"$HOME/backup"}

require_dir "${BACKUP_REPOS_BASEDIR}"
require_dir "${BACKUP_DIR}"

log_info "Using ${BACKUP_DIR} as backup destination directory"

find_repos "${BACKUP_REPOS_BASEDIR}" | while read repoDir
do
	backup_repo "${repoDir}" "${BACKUP_DIR}"
done
