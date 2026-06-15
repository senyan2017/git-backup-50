#!/bin/sh
#
# Restore a single git repository from multiple bundle files.
#
# Run this script from the directory containing backup bundle files,
# or pass the bundle directory as a third argument.
#
# Usage: backup-git-restore.sh <restore_dir> <repo_name> [<bundle_dir>]
# Restores the repository <repo_name> from bundle files named "<repo_name>_*.bundle"
# into a new git repository "<restore_dir>/<repo_name>".
# <bundle_dir> defaults to the current working directory.
#

if [ $# -ne 2 ] && [ $# -ne 3 ]; then
	echo "Usage: $(basename "$0") <restore_dir> <repo_name> [<bundle_dir>]" >&2
	echo "Example: $(basename "$0") /tmp/git/ repo" >&2
	echo "         $(basename "$0") /tmp/git/ repo /path/to/bundles" >&2
	exit 1
fi

RESTORE_DIR="$1"
REPO="$2"
BUNDLE_DIR="${3:-.}"
REPO_DIR="${RESTORE_DIR}/${REPO}"

# --- input validation -------------------------------------------------------

if [ -z "${RESTORE_DIR}" ]; then
	echo "ERROR: [input] restore_dir must not be empty" >&2
	exit 1
fi

if [ -z "${REPO}" ]; then
	echo "ERROR: [input] repo_name must not be empty" >&2
	exit 1
fi

if [ ! -d "${BUNDLE_DIR}" ]; then
	echo "ERROR: [path] bundle directory does not exist: ${BUNDLE_DIR}" >&2
	exit 1
fi

# Resolve bundle dir to absolute path so we can reference it reliably
BUNDLE_DIR="$(cd "${BUNDLE_DIR}" && pwd)"

if [ ! -d "${RESTORE_DIR}" ]; then
	echo "ERROR: [path] restore directory does not exist: ${RESTORE_DIR}" >&2
	exit 1
fi

# Resolve restore dir to absolute path
RESTORE_DIR="$(cd "${RESTORE_DIR}" && pwd)"
REPO_DIR="${RESTORE_DIR}/${REPO}"

# --- collect and sort bundle files ------------------------------------------
# Use a glob instead of parsing `ls` output.  Sort explicitly so that the
# restore order is stable and chronological (timestamps in filenames sort
# lexicographically).

bundle_list=""
bundle_count=0
for f in "${BUNDLE_DIR}/${REPO}_"*.bundle; do
	[ -f "$f" ] || continue
	bundle_list="${bundle_list}${f}
"
	bundle_count=$((bundle_count + 1))
done

if [ "${bundle_count}" -eq 0 ]; then
	echo "ERROR: [input] no bundle files matching '${REPO}_*.bundle' found in '${BUNDLE_DIR}'" >&2
	exit 1
fi

# Sort the list (one path per line) for stable chronological order
sorted_bundles="$(printf '%s' "${bundle_list}" | sort)"

echo "INFO: found ${bundle_count} bundle file(s) for '${REPO}'"

# --- restore loop -----------------------------------------------------------

# Save the original directory so we can always return to it
origDir="$(pwd)"

echo "${sorted_bundles}" | while IFS= read -r bundleFile; do
	[ -z "${bundleFile}" ] && continue

	file="$(basename "${bundleFile}")"

	if [ -d "${REPO_DIR}" ]; then
		# repository already exists: verify then pull
		echo "INFO: verifying bundle '${file}' for '${REPO}'"
		if ! git -C "${REPO_DIR}" bundle verify "${bundleFile}"; then
			echo "ERROR: [git] bundle verification failed for '${file}'" >&2
			exit 1
		fi

		echo "INFO: pulling from bundle '${file}'..."
		if ! git -C "${REPO_DIR}" pull "${bundleFile}"; then
			echo "ERROR: [git] pull from bundle '${file}' failed" >&2
			exit 1
		fi
	else
		# no repository yet: verify then clone from the first bundle
		echo "INFO: verifying bundle '${file}' for '${REPO}'"
		if ! git bundle verify "${bundleFile}"; then
			echo "ERROR: [git] bundle verification failed for '${file}'" >&2
			exit 1
		fi

		echo "INFO: restoring '${REPO}' from bundle '${file}'..."
		if ! git clone "${bundleFile}" "${REPO_DIR}"; then
			echo "ERROR: [git] clone from bundle '${file}' failed" >&2
			exit 1
		fi
	fi
done
rc=$?

# The while-loop above may run in a subshell (due to the pipe), so an `exit 1`
# inside it only exits the subshell.  We check the pipeline exit code here.
if [ ${rc} -ne 0 ]; then
	echo "ERROR: [git] restoring '${REPO}' failed" >&2
	exit ${rc}
fi

echo "INFO: repository '${REPO}' restored successfully to '${REPO_DIR}'"
