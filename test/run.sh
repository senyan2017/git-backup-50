#!/bin/sh
#
# Tests for the git backup / restore scripts.
#
# 1. clones a repository from repo.bundle and creates several incremental
#    backups (default nested layout)
# 2. checks the new behaviour: nested layout, dry-run, name filter, branch
#    validation and option/argument validation
# 3. restores the repository from the bundles and checks a restore dry-run
#

set -u

GBACKUP_DIR="../src"
SRC=`readlink -f ${GBACKUP_DIR}`
TEST_BUNDLE="repo.bundle"
BACKUP_DIR="backups"
REPO_NAME="repoA"
TMP_DIR="/tmp/git"
TMP_REPO="${TMP_DIR}/${REPO_NAME}"

OUT=/tmp/git-backup-test.out

cleanup() {
	rm -rf "${BACKUP_DIR}" "${TMP_DIR}" "/tmp/git2" "${REPO_NAME}" notgit "${OUT}" 2>/dev/null
}

fail() {
	echo "FAIL: $1"
	cleanup
	exit 1
}

# start from a clean slate (in case a previous run was interrupted)
cleanup

# ---------------------------------------------------------------------------
# 1) create several incremental backups (nested layout = default)
# ---------------------------------------------------------------------------
for i in `seq 1 5`
do
	./test-fill-repo.sh "${TEST_BUNDLE}" "${REPO_NAME}" "${GBACKUP_DIR}" "${BACKUP_DIR}" || fail "backup iteration ${i}"
	sleep 1
done

[ -d "${BACKUP_DIR}/${REPO_NAME}" ] || fail "nested layout directory was not created"
nbundles=`ls "${BACKUP_DIR}/${REPO_NAME}"/${REPO_NAME}_*.bundle 2>/dev/null | wc -l`
[ "${nbundles}" -ge 1 ] || fail "no nested bundles were created"
echo "PASS: nested incremental backups (${nbundles} bundle(s))"

# ---------------------------------------------------------------------------
# 2) dry-run lists a plan for pending changes but must not create anything
# ---------------------------------------------------------------------------
# introduce a change so an incremental backup would happen (but don't back it up)
( cd "${REPO_NAME}" && echo "DRY" >> A && git commit -am "pending change" >/dev/null ) || fail "could not create pending change"
before=`ls "${BACKUP_DIR}/${REPO_NAME}" | wc -l`
"${SRC}/backup-git.sh" --dry-run "${REPO_NAME}" "${BACKUP_DIR}" > "${OUT}" 2>&1 || fail "dry-run exited non-zero"
grep -q "DRY-RUN" "${OUT}" || fail "dry-run banner missing"
grep -q "PLAN:" "${OUT}" || fail "dry-run did not list a plan"
after=`ls "${BACKUP_DIR}/${REPO_NAME}" | wc -l`
[ "${before}" -eq "${after}" ] || fail "dry-run created files"
echo "PASS: dry-run lists a plan without making changes"

# ---------------------------------------------------------------------------
# 3) name filter excludes non-matching repositories
# ---------------------------------------------------------------------------
"${SRC}/backup-git.sh" --name 'nomatch-*' "${REPO_NAME}" "${BACKUP_DIR}" > "${OUT}" 2>&1
grep -q "no repositories matched" "${OUT}" || fail "name filter did not exclude non-matching repo"
echo "PASS: name filter excludes non-matching repositories"

# ---------------------------------------------------------------------------
# 4) a missing branch is reported as an error (non-zero exit)
# ---------------------------------------------------------------------------
if "${SRC}/backup-git.sh" --branch doesnotexist "${REPO_NAME}" "${BACKUP_DIR}" > "${OUT}" 2>&1; then
	fail "backup with a missing branch should fail"
fi
grep -q "branch(es) not found" "${OUT}" || fail "missing-branch error message absent"
echo "PASS: missing branch reported as error"

# ---------------------------------------------------------------------------
# 5) directory with no repositories is handled gracefully
# ---------------------------------------------------------------------------
mkdir -p notgit
"${SRC}/backup-git.sh" notgit "${BACKUP_DIR}" > "${OUT}" 2>&1
grep -q "no repositories matched" "${OUT}" || fail "empty directory should report no repositories"
rm -rf notgit
echo "PASS: directory without repositories handled gracefully"

# ---------------------------------------------------------------------------
# 6) invalid option / layout are rejected
# ---------------------------------------------------------------------------
if "${SRC}/backup-git.sh" --layout bogus "${REPO_NAME}" "${BACKUP_DIR}" > "${OUT}" 2>&1; then
	fail "invalid layout should be rejected"
fi
grep -q "invalid --layout" "${OUT}" || fail "invalid layout message absent"
echo "PASS: invalid layout rejected"

# ---------------------------------------------------------------------------
# 7) restore from nested layout (all bundles must be applied, not just clone)
# ---------------------------------------------------------------------------
./test-restore-repo.sh "${REPO_NAME}" "${GBACKUP_DIR}" "${BACKUP_DIR}" || fail "restore failed"
[ -d "${TMP_REPO}/.git" ] || fail "restored repository is missing"
restored_head=`git -C "${TMP_REPO}" rev-parse HEAD`
expected_head=`git -C "${REPO_NAME}" rev-parse lastBackup`
[ "${restored_head}" = "${expected_head}" ] || fail "restored HEAD (${restored_head}) != last backup (${expected_head})"
echo "PASS: restore from nested layout (HEAD matches last backup)"

# ---------------------------------------------------------------------------
# 8) restore dry-run lists bundles without creating a repository
# ---------------------------------------------------------------------------
"${SRC}/backup-git-restore.sh" --source "${BACKUP_DIR}" --dry-run /tmp/git2 "${REPO_NAME}" > "${OUT}" 2>&1 || fail "restore dry-run exited non-zero"
grep -q "DRY-RUN" "${OUT}" || fail "restore dry-run banner missing"
[ ! -d "/tmp/git2/${REPO_NAME}" ] || fail "restore dry-run created a repository"
echo "PASS: restore dry-run made no changes"

echo "OK"
cleanup
exit 0
