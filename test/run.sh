#!/bin/sh
#
# Test runner for the git backup scripts.
#
# 1. Happy path: a repository is cloned from repo.bundle and filled with
#    10 dummy commits; after every change an incremental bundle is created in
#    ./backups. Afterwards the repository is restored from the bundle files.
# 2. Regression suite: see test-regression.sh (paths with spaces, missing
#    bundles, incomplete restore targets, bundle ordering, tag matching).
#

TEST_BACKUP_DIR="backups"
TEST_BUNDLE="repo.bundle"
GBACKUP_DIR="../src"
REPO_NAME="repoA"
TMP_DIR="/tmp/git"
TMP_REPO="${TMP_DIR}/${REPO_NAME}"

overall=0

echo "=== happy path: 10 incremental backups + restore ==="
i=1
while [ "${i}" -le 10 ]
do
	./test-fill-repo.sh "${TEST_BUNDLE}" "${TMP_REPO}" "${GBACKUP_DIR}" "${TEST_BACKUP_DIR}"
	sleep 1
	i=$((i + 1))
done

./test-restore-repo.sh "${REPO_NAME}" "${GBACKUP_DIR}" "${TEST_BACKUP_DIR}"
rc=$?

if [ "${rc}" -eq 0 ]; then
	echo "happy path: OK"
else
	echo "happy path: ERROR"
	overall=1
fi

rm -Rf "${TEST_BACKUP_DIR}"
rm -Rf "${TMP_DIR}"

echo
echo "=== regression suite ==="
./test-regression.sh
rc=$?

if [ "${rc}" -eq 0 ]; then
	echo "regression: OK"
else
	echo "regression: ERROR"
	overall=1
fi

echo
if [ "${overall}" -eq 0 ]; then
	echo "OK"
else
	echo "ERROR"
fi

exit "${overall}"
