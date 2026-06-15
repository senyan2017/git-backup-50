#!/bin/sh
#
# backup-git.sh - create incremental bundle backups of git repositories.
#
# Usage: backup-git.sh <repository_dir> [<backup_dir>]
#
# Searches for git repositories (containing a .git directory) inside
# <repository_dir> and writes incremental bundle files to <backup_dir>.
# Bundle filename pattern: <repo_name>_YYYYmmdd-HHMMSS.bundle
#
# The tag "lastBackup" marks the last commit that was included in a bundle,
# so subsequent runs only export commits added since the previous backup.
#

. "$(dirname "$0")/lib.sh"

# ── Arguments ─────────────────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
	echo "Usage: $0 <repository_dir> [<backup_dir>]"
	exit 0
fi

BACKUP_REPOS_BASEDIR="$1"
BACKUP_DIR="${2:-$HOME/backup}"

require_dir "${BACKUP_REPOS_BASEDIR}" "repository dir '${BACKUP_REPOS_BASEDIR}'"
require_dir "${BACKUP_DIR}"           "backup dir '${BACKUP_DIR}'"

log_info "Using ${BACKUP_DIR} as backup destination directory"

# ── Step: generate bundle for a single repository ────────────────────────────
#
# $1 - absolute path to the repository working tree (the dir that contains .git)
#
# Behaviour:
#   - If no BACKUP_TAG exists yet, export the full history (--all).
#   - If the tag exists but there are no new commits, skip.
#   - Otherwise export only the incremental range BACKUP_TAG..master.
#   - Verify the bundle and move the tag to master.
backup_repo() {
	repoDir="$1"
	repoName="$(basename "${repoDir}")"
	datetime="$(date +%Y%m%d-%H%M%S)"
	fileName="${BACKUP_DIR}/${repoName}_${datetime}.bundle"

	log_info "processing ${repoName}..."

	enter_dir "${repoDir}"

	# Decide what range to export.
	if [ "$(git tag | grep -c "^${BACKUP_TAG}$")" -eq 0 ]; then
		# First-ever backup: export everything.
		log_info "exporting ${repoName} to $(basename "${fileName}")"
		git bundle create "${fileName}" --all

	else
		# Incremental backup: only commits since the last tag.
		newCommits="$(git log "${BACKUP_TAG}..master" --oneline | wc -l)"
		if [ "${newCommits}" -eq 0 ]; then
			log_info "no changes since last backup — skipping ${repoName}"
			leave_dir
			return
		fi

		log_info "'${BACKUP_TAG}' tag points to $(git rev-parse "${BACKUP_TAG}^0")"
		log_info "exporting '${repoName}' (${BACKUP_TAG}..master) to $(basename "${fileName}")"
		git bundle create "${fileName}" --all "${BACKUP_TAG}..master"
	fi

	# Verify the bundle we just created.
	log_info "verifying bundle '$(basename "${fileName}")'"
	bundle_verify "${fileName}" || die "bundle verification failed for ${fileName}"

	# Move the tag forward to master so the next run is incremental again.
	log_info "moving tag '${BACKUP_TAG}' to master"
	git tag -f "${BACKUP_TAG}" master

	leave_dir
}

# ── Step: discover repositories and run backup ────────────────────────────────

find "${BACKUP_REPOS_BASEDIR}" -maxdepth 2 -type d -name '.git' | while read -r gitDir
do
	repoDir="$(dirname "${gitDir}")"
	backup_repo "${repoDir}"
done
