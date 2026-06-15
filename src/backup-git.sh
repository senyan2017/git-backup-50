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

if [ $# -lt 1 ]; then
	echo "Usage: $(basename "$0") <repository_dir> [<backup_dir>]" >&2
	exit 1
fi

BACKUP_REPOS_BASEDIR="$1"
BACKUP_DIR="${2:-"$HOME/backup"}"
BACKUP_TAG="lastBackup"

if [ ! -d "${BACKUP_REPOS_BASEDIR}" ]; then
	echo "ERROR: [path] not a directory: ${BACKUP_REPOS_BASEDIR}" >&2
	exit 1
fi

if [ ! -d "${BACKUP_DIR}" ]; then
	echo "ERROR: [path] backup destination is not a directory: ${BACKUP_DIR}" >&2
	exit 1
fi

# Resolve to absolute paths to avoid issues with relative path references
BACKUP_REPOS_BASEDIR="$(cd "${BACKUP_REPOS_BASEDIR}" && pwd)"
BACKUP_DIR="$(cd "${BACKUP_DIR}" && pwd)"

echo "INFO: using '${BACKUP_DIR}' as backup destination directory"

# The find|while pipeline runs in a subshell on some shells (dash, bash),
# so we communicate failures through a temp file.
errfile="$(mktemp)"
foundfile="$(mktemp)"
trap 'rm -f "${errfile}" "${foundfile}"' EXIT

# Use IFS= read -r to handle directory names with spaces and special chars.
# -maxdepth 2 allows repos at BASEDIR/repo/.git (one level of nesting).
find "${BACKUP_REPOS_BASEDIR}" -maxdepth 2 -type d -name '.git' | while IFS= read -r repoGitDir; do
	repoDir="$(dirname "${repoGitDir}")"
	repoName="$(basename "${repoDir}")"

	echo "INFO: processing '${repoName}'..."

	# Detect the default branch (HEAD) instead of hardcoding master
	if ! defaultBranch="$(git -C "${repoDir}" symbolic-ref --short HEAD 2>/dev/null)"; then
		echo "ERROR: [git] cannot determine current branch for '${repoName}' (detached HEAD?)" >&2
		echo "1" >> "${errfile}"
		continue
	fi

	datetime="$(date +%Y%m%d-%H%M%S)"
	fileName="${BACKUP_DIR}/${repoName}_${datetime}.bundle"

	echo "INFO: checking tag '${BACKUP_TAG}'"
	tagCount="$(git -C "${repoDir}" tag -l "${BACKUP_TAG}" | wc -l)"

	if [ "${tagCount}" -eq 0 ]; then
		# no backup was ever made, create initial bundle
		echo "INFO: exporting '${repoName}' to '${fileName}'"
		if ! git -C "${repoDir}" bundle create "${fileName}" --all; then
			echo "ERROR: [git] bundle create failed for '${repoName}'" >&2
			echo "1" >> "${errfile}"
			continue
		fi
	else
		# tag pointing to previous backup found

		# check for commits since last backup
		changeCount="$(git -C "${repoDir}" log "${BACKUP_TAG}..${defaultBranch}" --oneline 2>/dev/null | wc -l)"
		if [ "${changeCount}" -eq 0 ]; then
			echo "INFO: no changes since last backup for '${repoName}'"
			continue
		fi

		# create incremental bundle containing changes since last backup
		echo "INFO: '${BACKUP_TAG}' tag:"
		git -C "${repoDir}" rev-parse "${BACKUP_TAG}^0"

		echo "INFO: exporting '${repoName}' (${BACKUP_TAG}..${defaultBranch}) to '${fileName}'"
		if ! git -C "${repoDir}" bundle create "${fileName}" --all "${BACKUP_TAG}..${defaultBranch}"; then
			echo "ERROR: [git] incremental bundle create failed for '${repoName}'" >&2
			echo "1" >> "${errfile}"
			continue
		fi
	fi

	echo "INFO: verifying bundle '${fileName}'"
	if ! git -C "${repoDir}" bundle verify "${fileName}"; then
		echo "ERROR: [git] bundle verification failed for '${fileName}'" >&2
		echo "1" >> "${errfile}"
		continue
	fi

	echo "INFO: updating tag '${BACKUP_TAG}' to '${defaultBranch}'"
	if ! git -C "${repoDir}" tag -f "${BACKUP_TAG}" "${defaultBranch}"; then
		echo "ERROR: [git] failed to update tag '${BACKUP_TAG}' in '${repoName}'" >&2
		echo "1" >> "${errfile}"
		continue
	fi

	echo "1" >> "${foundfile}"
done

# Check if any errors were recorded
if [ -s "${errfile}" ]; then
	echo "ERROR: one or more repositories failed to back up" >&2
	exit 1
fi

echo "INFO: backup complete"
