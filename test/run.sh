#!/bin/sh
#
# Round-trip test for the git backup scripts.
#
# It runs two clearly separated phases so a failure tells you which side broke:
#
#   backup phase  - clone a repo from repo.bundle, then repeatedly commit and
#                   create an incremental bundle (exercises backup-git.sh).
#   restore phase - rebuild the repository from those bundles into /tmp/git
#                   (exercises backup-git-restore.sh).
#
# Prints "OK" / "ERROR" and exits 0 only when both phases succeed.
#

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "${SCRIPT_DIR}/lib-test.sh"

cd "${SCRIPT_DIR}"

TEST_BUNDLE="repo.bundle"
TEST_BACKUP_DIR="backups"
GBACKUP_DIR="../src"
REPO_NAME="repoA"
TMP_DIR="/tmp/git"
TMP_REPO="${TMP_DIR}/${REPO_NAME}"
COMMITS=10

cleanup() {
	rm -Rf "${TEST_BACKUP_DIR}"
	rm -Rf "${TMP_DIR}"
	rm -Rf "${REPO_NAME}"
}

# --- backup phase ------------------------------------------------------------
log_info "=== backup phase: ${COMMITS} commit+bundle iterations ==="
i=1
while [ "${i}" -le "${COMMITS}" ]; do
	if ! ./test-fill-repo.sh "${TEST_BUNDLE}" "${TMP_REPO}" "${GBACKUP_DIR}" "${TEST_BACKUP_DIR}"; then
		log_error "backup chain failed on iteration ${i}"
		cleanup
		echo "ERROR"
		exit 1
	fi
	# Distinct second-precision timestamps keep bundle filenames unique.
	sleep 1
	i=$((i + 1))
done

# --- restore phase -----------------------------------------------------------
log_info "=== restore phase: restoring ${REPO_NAME} from bundles ==="
./test-restore-repo.sh "${REPO_NAME}" "${GBACKUP_DIR}" "${TEST_BACKUP_DIR}"
rc=$?

if [ "${rc}" -eq 0 ]; then
	log_info "restore chain OK"
else
	log_error "restore chain failed (rc=${rc})"
fi

cleanup

if [ "${rc}" -eq 0 ]; then
	echo "OK"
else
	echo "ERROR"
fi

exit "${rc}"
