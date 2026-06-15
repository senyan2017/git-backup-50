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
# <backup_dir> defaults to "$HOME/backup".
# Bundle filename pattern "<repository_name>_YYYYmmdd-HHMMSS.bundle"
#
# Only the "master" branch is backed up (override with the BRANCH environment variable).
# Repositories without that branch are skipped with a clear error and do not abort the run.
#

BACKUP_TAG="lastBackup"
BRANCH="${BRANCH:-master}"

# Resolve a directory to its absolute, physical path.
# Prints nothing and returns non-zero if the directory does not exist.
abspath() {
	( cd "$1" 2>/dev/null && pwd -P )
}

if [ $# -lt 1 ]; then
	echo "Usage: $0 <repository_dir> [<backup_dir>]" >&2
	echo "ERROR: [input] missing <repository_dir> argument" >&2
	exit 2
fi

BACKUP_REPOS_BASEDIR=$1
BACKUP_DIR=${2:-"$HOME/backup"}

if [ ! -d "${BACKUP_REPOS_BASEDIR}" ]; then
	echo "ERROR: [path] repository dir '${BACKUP_REPOS_BASEDIR}' is not a directory" >&2
	exit 1
fi

if [ ! -d "${BACKUP_DIR}" ]; then
	echo "ERROR: [path] backup dir '${BACKUP_DIR}' is not a directory" >&2
	exit 1
fi

# Resolve to absolute paths so that changing into a repository later does not
# break relative backup destinations or relative repository paths.
BACKUP_REPOS_BASEDIR=$(abspath "${BACKUP_REPOS_BASEDIR}") || {
	echo "ERROR: [path] cannot access repository dir '$1'" >&2
	exit 1
}
BACKUP_DIR=$(abspath "${BACKUP_DIR}") || {
	echo "ERROR: [path] cannot access backup dir '${BACKUP_DIR}'" >&2
	exit 1
}

echo "INFO: Using ${BACKUP_DIR} as backup destination directory"

# Collect repositories into a temp file first, then iterate in the *current*
# shell (a pipe into 'while' would run the loop in a subshell and lose the
# failure counter). IFS= and 'read -r' keep paths with spaces/backslashes intact.
repoList=$(mktemp "${TMPDIR:-/tmp}/git-backup-list.XXXXXX") || {
	echo "ERROR: [path] cannot create temporary file" >&2
	exit 1
}
trap 'rm -f "${repoList}"' EXIT INT TERM

# find git repositories (directories that contain a .git directory)
find "${BACKUP_REPOS_BASEDIR}" -maxdepth 2 -type d -name '.git' > "${repoList}"

if [ ! -s "${repoList}" ]; then
	echo "INFO: no git repositories found under '${BACKUP_REPOS_BASEDIR}'"
	exit 0
fi

failures=0
processed=0

while IFS= read -r repoDir
do
	[ -n "${repoDir}" ] || continue

	dir=$(dirname "${repoDir}")
	repoName=$(basename "${dir}")
	processed=$((processed + 1))

	echo "INFO: processing ${repoName}..."

	datetime=$(date +%Y%m%d-%H%M%S)
	fileName="${BACKUP_DIR}/${repoName}_${datetime}.bundle"

	if ! cd "${dir}"; then
		echo "ERROR: [path] cannot enter repository '${dir}'" >&2
		failures=$((failures + 1))
		continue
	fi

	# Make sure the branch we are supposed to back up actually exists,
	# otherwise the bundle range below would fail with an obscure git error.
	if ! git rev-parse -q --verify "refs/heads/${BRANCH}" >/dev/null; then
		echo "ERROR: [git] branch '${BRANCH}' not found in '${repoName}', skipping" >&2
		failures=$((failures + 1))
		cd "${BACKUP_REPOS_BASEDIR}" || exit 1
		continue
	fi

	echo "INFO: checking tag '${BACKUP_TAG}'"
	if ! git rev-parse -q --verify "refs/tags/${BACKUP_TAG}" >/dev/null; then
		# no backup was ever made, create initial bundle
		echo "INFO: exporting ${repoName} to ${fileName}"
		if ! git bundle create "${fileName}" --all; then
			echo "ERROR: [git] creating initial bundle for '${repoName}' failed" >&2
			failures=$((failures + 1))
			cd "${BACKUP_REPOS_BASEDIR}" || exit 1
			continue
		fi
	else
		# tag pointing to previous backup found

		# check for commits since last backup
		if [ "$(git log "${BACKUP_TAG}..${BRANCH}" --oneline | wc -l)" -eq 0 ]; then
			echo "INFO: no changes since last backup!"
			cd "${BACKUP_REPOS_BASEDIR}" || exit 1
			continue
		fi

		# create incremental bundle containing changes since last backup
		echo "INFO: '${BACKUP_TAG}' tag:"
		git rev-parse "${BACKUP_TAG}^0"

		echo "INFO: exporting '${repoName}' (${BACKUP_TAG}..${BRANCH}) to ${fileName}"
		if ! git bundle create "${fileName}" --all "${BACKUP_TAG}..${BRANCH}"; then
			echo "ERROR: [git] creating incremental bundle for '${repoName}' failed" >&2
			failures=$((failures + 1))
			cd "${BACKUP_REPOS_BASEDIR}" || exit 1
			continue
		fi
	fi

	echo "INFO: verifying bundle '${fileName}'"
	if ! git bundle verify "${fileName}"; then
		echo "ERROR: [git] bundle verification failed for '${repoName}'" >&2
		failures=$((failures + 1))
		cd "${BACKUP_REPOS_BASEDIR}" || exit 1
		continue
	fi

	echo "INFO: creating tag '${BACKUP_TAG}'"
	git tag -f "${BACKUP_TAG}" "${BRANCH}"

	cd "${BACKUP_REPOS_BASEDIR}" || exit 1
done < "${repoList}"

if [ "${failures}" -ne 0 ]; then
	echo "ERROR: [git] ${failures} of ${processed} repositor(y/ies) failed to back up" >&2
	exit 1
fi

echo "INFO: ${processed} repositor(y/ies) backed up successfully"
