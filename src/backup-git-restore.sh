#!/bin/sh
#
# Restore a single git repository from multiple bundle files.
#
# Run this script inside a directory that contains the backup bundle files.
#
# Usage: backup-git-restore.sh <restore_dir> <repo_name>
# Restores the repository <repo_name> from bundle files named "<repo_name>_*.bundle"
# (found in the current directory) into a new git repository "<restore_dir>/<repo_name>".
#
# Bundle files are applied in chronological order (their names embed a
# YYYYmmdd-HHMMSS timestamp); the oldest bundle is used to create the repository
# and the remaining bundles are pulled on top of it.
#

# Force deterministic, ASCII collation so the bundle glob below is always
# expanded in a stable (chronological) order regardless of the user's locale.
export LC_COLLATE=C

if [ $# -ne 2 ]; then
	echo "Usage: $(basename "$0") <restore_dir> <repo_name>" >&2
	echo "Example: $(basename "$0") /tmp/git repo" >&2
	echo "ERROR: [input] expected exactly 2 arguments, got $#" >&2
	exit 2
fi

RESTORE_DIR=$1
REPO=$2

# Directory that holds the bundle files (the current working directory).
backupDir=$(pwd -P)

# Make the restore destination absolute so we never depend on the current
# working directory while applying the bundles.
case "${RESTORE_DIR}" in
	/*) ;;
	*) RESTORE_DIR="${backupDir}/${RESTORE_DIR}" ;;
esac
REPO_DIR="${RESTORE_DIR}/${REPO}"

# Collect matching bundle files via a glob (space-safe, deterministically
# ordered) instead of parsing 'ls'. If nothing matches, the literal pattern
# is left untouched, which we detect with the existence test below.
set -- "${backupDir}/${REPO}"_*.bundle
if [ ! -e "$1" ]; then
	echo "ERROR: [path] no bundle files matching '${REPO}_*.bundle' found in '${backupDir}'" >&2
	exit 3
fi

rc=1

for bundleFile in "$@"
do
	file=$(basename "${bundleFile}")

	if [ -d "${REPO_DIR}" ]; then
		# The target already exists: it must be a valid git repository,
		# otherwise a leftover/partial directory would cause obscure failures.
		if ! git -C "${REPO_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			echo "ERROR: [git] restore target '${REPO_DIR}' exists but is not a valid git repository" >&2
			exit 4
		fi

		# verify bundle against the repository (must run inside the repo)
		echo "INFO: verifying bundle '${file}' for '${REPO}'"
		if git -C "${REPO_DIR}" bundle verify "${bundleFile}"; then
			:
		else
			rc=$?
			echo "ERROR: [git] verification failed for '${file}': ${rc}" >&2
			exit "${rc}"
		fi

		# pull changes from the bundle
		echo "INFO: pulling from bundle '${file}'..."
		if git -C "${REPO_DIR}" pull "${bundleFile}"; then
			:
		else
			rc=$?
			echo "ERROR: [git] pull failed for '${file}': ${rc}" >&2
			exit "${rc}"
		fi
		rc=0
	else
		# No repository yet. 'git bundle verify' needs an existing repository,
		# so do a repository-less sanity check with 'list-heads' and let
		# 'git clone' validate prerequisites and create the repository.
		echo "INFO: verifying bundle '${file}' for '${REPO}'"
		if git bundle list-heads "${bundleFile}" >/dev/null 2>&1; then
			:
		else
			rc=$?
			echo "ERROR: [git] '${file}' is not a readable bundle file: ${rc}" >&2
			exit "${rc}"
		fi

		# create new repository using the first (oldest) bundle file
		echo "INFO: restoring repo ${REPO} from bundle '${file}'..."
		if git clone "${bundleFile}" "${REPO_DIR}"; then
			:
		else
			rc=$?
			echo "ERROR: [git] clone failed for '${file}': ${rc}" >&2
			echo "ERROR: [git] cannot create repository from '${file}' (missing prerequisites?)" >&2
			exit "${rc}"
		fi
		rc=0
	fi
done

if [ "${rc}" -eq 0 ]; then
	echo "INFO: repository ${REPO} restored successfully into ${REPO_DIR}"
else
	echo "ERROR: [git] restoring failed: ${rc}" >&2
	exit "${rc}"
fi
