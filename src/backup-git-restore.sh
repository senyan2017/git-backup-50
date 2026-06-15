#!/bin/sh
#
# backup-git-restore.sh - restore a git repository from bundle files.
#
# Usage: backup-git-restore.sh <restore_dir> <repo_name>
#
# Reads all bundle files named "<repo_name>_*.bundle" in the current
# directory (in lexicographic order) and replays them in sequence:
#   - the first bundle creates a fresh clone at <restore_dir>/<repo_name>
#   - each subsequent bundle is pulled into the existing repository
#
# Exits 0 when at least one bundle was applied successfully.
#

. "$(dirname "$0")/lib.sh"

# ── Arguments ─────────────────────────────────────────────────────────────────

if [ $# -ne 2 ]; then
	echo "Usage: $(basename "$0") <restore_dir> <repo_name>"
	echo "Example: $(basename "$0") /tmp/git/ repo"
	exit 1
fi

RESTORE_DIR="$1"
REPO="$2"
REPO_DIR="${RESTORE_DIR}/${REPO}"

# ── Step: apply a single bundle ──────────────────────────────────────────────
#
# $1 - absolute path to the bundle file
#
# If the repo already exists: verify + pull.
# Otherwise: verify + clone.
apply_bundle() {
	bundleFile="$1"
	bundleName="$(basename "${bundleFile}")"

	if [ -d "${REPO_DIR}" ]; then
		# Repo already exists: verify prerequisites against it, then pull.
		enter_dir "${REPO_DIR}"
		log_info "verifying bundle '${bundleName}' for '${REPO}'"
		bundle_verify "${bundleFile}" || die "verification failed for ${bundleName}"
		log_info "pulling from bundle '${bundleName}'..."
		git pull "${bundleFile}" || die "pull failed for ${bundleName}"
		leave_dir
	else
		# First bundle: verify standalone, then clone to create the repo.
		log_info "verifying bundle '${bundleName}' for '${REPO}'"
		bundle_verify "${bundleFile}" || die "verification failed for ${bundleName}"
		log_info "restoring repo '${REPO}' from bundle '${bundleName}'..."
		git clone "${bundleFile}" "${REPO_DIR}" || die "clone failed for ${bundleName}"
	fi
}

# ── Step: replay all bundles in order ─────────────────────────────────────────
#
# We run from the caller's current directory, which must contain the bundles.
rc=1  # stays 1 if the loop body never executes

for file in $(ls "${REPO}"_*.bundle 2>/dev/null); do
	bundleFile="$(pwd)/${file}"
	apply_bundle "${bundleFile}"
	rc=0
done

# ── Result ────────────────────────────────────────────────────────────────────

if [ "${rc}" -eq 0 ]; then
	log_info "repository '${REPO}' restored successfully"
else
	log_error "restoring failed (no bundles found or last operation failed): rc=${rc}"
	exit "${rc}"
fi
