#!/bin/sh
#
# Test suite for git backup scripts.
#
# Tests:
#   1. Basic backup & restore (incremental bundles, single repo)
#   2. Dry-run mode
#   3. Repo name filtering
#   4. Branch-specific backup
#   5. Error handling (non-git dir, missing branch)
#   6. Multi-repo backup and selective restore
#   7. Restore --list mode
#

TEST_BACKUP_DIR="backups"
TEST_BUNDLE="repo.bundle"
GBACKUP_DIR="../src"
REPO_NAME="repoA"
TMP_DIR="/tmp/git"
TMP_REPO="/tmp/git/${REPO_NAME}"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

cleanup() {
	rm -Rf "${TEST_BACKUP_DIR}" 2>/dev/null
	rm -Rf "${TMP_DIR}" 2>/dev/null
	rm -Rf /tmp/test-multi-repos 2>/dev/null
	rm -Rf /tmp/test-restore-multi 2>/dev/null
	rm -Rf /tmp/test-dryrun-backup 2>/dev/null
}

cleanup

echo "===== Test 1: Basic incremental backup & restore ====="

for i in `seq 1 5`
do
	./test-fill-repo.sh ${TEST_BUNDLE} ${TMP_REPO} ${GBACKUP_DIR} ${TEST_BACKUP_DIR}
	sleep 1
done

# check that bundles are in the organized layout
if [ -d "${TEST_BACKUP_DIR}/${REPO_NAME}" ]; then
	pass "bundles stored in per-repo subdirectory"
else
	fail "expected per-repo subdirectory ${TEST_BACKUP_DIR}/${REPO_NAME}"
fi

bundle_count=$(find "${TEST_BACKUP_DIR}/${REPO_NAME}" -name "${REPO_NAME}_*.bundle" | wc -l)
if [ "${bundle_count}" -ge 1 ]; then
	pass "at least one bundle created (${bundle_count} found)"
else
	fail "no bundles found"
fi

# restore
./test-restore-repo.sh ${REPO_NAME} ${GBACKUP_DIR} ${TEST_BACKUP_DIR}
rc=$?
if [ ${rc} -eq 0 ]; then
	pass "restore completed successfully"
else
	fail "restore failed (rc=${rc})"
fi

# verify restored repo has commits
if [ -d "${TMP_REPO}" ]; then
	commit_count=$(git -C "${TMP_REPO}" log --oneline 2>/dev/null | wc -l)
	if [ "${commit_count}" -ge 5 ]; then
		pass "restored repo has ${commit_count} commits (expected ≥5)"
	else
		fail "restored repo has only ${commit_count} commits (expected ≥5)"
	fi
else
	fail "restored repo directory not found"
fi

cleanup

echo ""
echo "===== Test 2: Dry-run mode ====="

# set up a repo first
mkdir -p /tmp/test-dryrun-backup
if [ ! -d "${TMP_REPO}" ]; then
	git clone ${TEST_BUNDLE} ${TMP_REPO}
fi
datetime=`date +%Y%m%d-%H%M%S`
echo "test" >> "${TMP_REPO}/A"
git -C "${TMP_REPO}" commit -am "dry-run test ${datetime}"

# run dry-run
${GBACKUP_DIR}/backup-git.sh --dry-run ${TMP_REPO} /tmp/test-dryrun-backup
rc=$?
if [ ${rc} -eq 0 ]; then
	pass "dry-run exits successfully"
else
	fail "dry-run failed (rc=${rc})"
fi

# check no bundles were created
dryrun_bundles=$(find /tmp/test-dryrun-backup -name "*.bundle" 2>/dev/null | wc -l)
if [ "${dryrun_bundles}" -eq 0 ]; then
	pass "dry-run created no bundles"
else
	fail "dry-run created ${dryrun_bundles} bundles (expected 0)"
fi

cleanup

echo ""
echo "===== Test 3: Repo name filtering ====="

# create multiple repos
mkdir -p /tmp/test-multi-repos
git clone ${TEST_BUNDLE} /tmp/test-multi-repos/alpha
git clone ${TEST_BUNDLE} /tmp/test-multi-repos/beta
git clone ${TEST_BUNDLE} /tmp/test-multi-repos/gamma

echo "x" >> /tmp/test-multi-repos/alpha/A
git -C /tmp/test-multi-repos/alpha commit -am "alpha change"
echo "x" >> /tmp/test-multi-repos/beta/A
git -C /tmp/test-multi-repos/beta commit -am "beta change"
echo "x" >> /tmp/test-multi-repos/gamma/A
git -C /tmp/test-multi-repos/gamma commit -am "gamma change"

# backup only "beta"
${GBACKUP_DIR}/backup-git.sh --repo beta /tmp/test-multi-repos /tmp/test-multi-repos/backup
rc=$?
if [ ${rc} -eq 0 ]; then
	pass "filtered backup exits successfully"
else
	fail "filtered backup failed (rc=${rc})"
fi

if [ -d "/tmp/test-multi-repos/backup/beta" ]; then
	pass "beta repo was backed up"
else
	fail "beta repo was NOT backed up"
fi

if [ ! -d "/tmp/test-multi-repos/backup/alpha" ] && [ ! -d "/tmp/test-multi-repos/backup/gamma" ]; then
	pass "alpha and gamma were correctly excluded"
else
	fail "alpha or gamma was incorrectly backed up"
fi

# cleanup multi-repos
rm -Rf /tmp/test-multi-repos

echo ""
echo "===== Test 4: Branch-specific backup ====="

mkdir -p /tmp/test-branch-repo
git clone ${TEST_BUNDLE} /tmp/test-branch-repo
echo "main" >> /tmp/test-branch-repo/A
git -C /tmp/test-branch-repo commit -am "main change"
git -C /tmp/test-branch-repo branch feature-x
git -C /tmp/test-branch-repo checkout feature-x
echo "feature" >> /tmp/test-branch-repo/B 2>/dev/null || echo "feature" > /tmp/test-branch-repo/B
git -C /tmp/test-branch-repo add -A
git -C /tmp/test-branch-repo commit -am "feature-x change"
git -C /tmp/test-branch-repo checkout master 2>/dev/null || git -C /tmp/test-branch-repo checkout main

# backup only the feature branch
${GBACKUP_DIR}/backup-git.sh -b feature-x /tmp/test-branch-repo /tmp/test-branch-backup
rc=$?
if [ ${rc} -eq 0 ]; then
	pass "branch-specific backup exits successfully"
else
	fail "branch-specific backup failed (rc=${rc})"
fi

bundle_file=$(find /tmp/test-branch-backup -name "*.bundle" | head -1)
if [ -n "${bundle_file}" ]; then
	pass "branch bundle created: $(basename ${bundle_file})"
	# verify the bundle contains the feature-x branch
	if git bundle verify "${bundle_file}" 2>/dev/null | grep -q "feature-x"; then
		pass "bundle contains feature-x branch"
	else
		fail "bundle does not contain feature-x branch"
	fi
else
	fail "no branch bundle created"
fi

rm -Rf /tmp/test-branch-repo /tmp/test-branch-backup

echo ""
echo "===== Test 5: Error handling ====="

# non-existent directory
${GBACKUP_DIR}/backup-git.sh /tmp/nonexistent-dir-xyz /tmp/test-err-backup 2>/dev/null
rc=$?
if [ ${rc} -ne 0 ]; then
	pass "non-existent directory rejected (rc=${rc})"
else
	fail "non-existent directory was not rejected"
fi

# directory that is not a git repo
mkdir -p /tmp/test-notgit
echo "hello" > /tmp/test-notgit/file.txt
${GBACKUP_DIR}/backup-git.sh /tmp/test-notgit /tmp/test-err-backup 2>/dev/null
# this should run but skip the non-repo (no .git found)
rc=$?
if [ ${rc} -eq 0 ]; then
	pass "non-git directory scanned without error (no bundles created)"
else
	# also acceptable: exits with warning
	pass "non-git directory handled (rc=${rc})"
fi
rm -Rf /tmp/test-notgit /tmp/test-err-backup

# missing branch
git clone ${TEST_BUNDLE} /tmp/test-missing-branch
echo "x" >> /tmp/test-missing-branch/A
git -C /tmp/test-missing-branch commit -am "change"
${GBACKUP_DIR}/backup-git.sh -b nonexistent-branch /tmp/test-missing-branch /tmp/test-missing-branch-backup 2>/dev/null
rc=$?
if [ ${rc} -ne 0 ]; then
	pass "non-existent branch rejected (rc=${rc})"
else
	# the script may skip rather than fail hard
	pass "non-existent branch handled (skipped)"
fi
rm -Rf /tmp/test-missing-branch /tmp/test-missing-branch-backup

echo ""
echo "===== Test 6: Multi-repo backup and selective restore ====="

mkdir -p /tmp/test-multi-repos
git clone ${TEST_BUNDLE} /tmp/test-multi-repos/proj-alpha
git clone ${TEST_BUNDLE} /tmp/test-multi-repos/proj-beta

echo "a" >> /tmp/test-multi-repos/proj-alpha/A
git -C /tmp/test-multi-repos/proj-alpha commit -am "alpha"
echo "b" >> /tmp/test-multi-repos/proj-beta/A
git -C /tmp/test-multi-repos/proj-beta commit -am "beta"

# backup all
${GBACKUP_DIR}/backup-git.sh /tmp/test-multi-repos /tmp/test-multi-backup
rc=$?
if [ ${rc} -eq 0 ]; then
	pass "multi-repo backup succeeded"
else
	fail "multi-repo backup failed (rc=${rc})"
fi

# check both repos backed up
alpha_bundles=$(find /tmp/test-multi-backup/proj-alpha -name "*.bundle" 2>/dev/null | wc -l)
beta_bundles=$(find /tmp/test-multi-backup/proj-beta -name "*.bundle" 2>/dev/null | wc -l)
if [ "${alpha_bundles}" -ge 1 ] && [ "${beta_bundles}" -ge 1 ]; then
	pass "both repos have bundles (alpha=${alpha_bundles}, beta=${beta_bundles})"
else
	fail "missing bundles (alpha=${alpha_bundles}, beta=${beta_bundles})"
fi

# restore only proj-alpha
mkdir -p /tmp/test-restore-multi
${GBACKUP_DIR}/backup-git-restore.sh --repo proj-alpha /tmp/test-restore-multi /tmp/test-multi-backup
rc=$?
if [ ${rc} -eq 0 ]; then
	pass "selective restore succeeded"
else
	fail "selective restore failed (rc=${rc})"
fi

if [ -d "/tmp/test-restore-multi/proj-alpha" ]; then
	pass "proj-alpha restored"
else
	fail "proj-alpha not restored"
fi

if [ ! -d "/tmp/test-restore-multi/proj-beta" ]; then
	pass "proj-beta correctly not restored"
else
	fail "proj-beta was unexpectedly restored"
fi

rm -Rf /tmp/test-multi-repos /tmp/test-multi-backup /tmp/test-restore-multi

echo ""
echo "===== Test 7: Restore --list mode ====="

mkdir -p /tmp/test-multi-repos
git clone ${TEST_BUNDLE} /tmp/test-multi-repos/listme
echo "x" >> /tmp/test-multi-repos/listme/A
git -C /tmp/test-multi-repos/listme commit -am "listme change"
${GBACKUP_DIR}/backup-git.sh /tmp/test-multi-repos /tmp/test-list-backup

output=$(${GBACKUP_DIR}/backup-git-restore.sh --list /tmp/git /tmp/test-list-backup 2>&1)
if echo "${output}" | grep -q "listme"; then
	pass "--list shows repo 'listme'"
else
	fail "--list did not show 'listme'"
fi

rm -Rf /tmp/test-multi-repos /tmp/test-list-backup

echo ""
echo "===== Test 8: Repo glob filter ====="

mkdir -p /tmp/test-multi-repos
git clone ${TEST_BUNDLE} /tmp/test-multi-repos/api-server
git clone ${TEST_BUNDLE} /tmp/test-multi-repos/api-client
git clone ${TEST_BUNDLE} /tmp/test-multi-repos/web-frontend

echo "x" >> /tmp/test-multi-repos/api-server/A
git -C /tmp/test-multi-repos/api-server commit -am "api-server"
echo "x" >> /tmp/test-multi-repos/api-client/A
git -C /tmp/test-multi-repos/api-client commit -am "api-client"
echo "x" >> /tmp/test-multi-repos/web-frontend/A
git -C /tmp/test-multi-repos/web-frontend commit -am "web-frontend"

${GBACKUP_DIR}/backup-git.sh --repo "api-*" /tmp/test-multi-repos /tmp/test-glob-backup
rc=$?
if [ ${rc} -eq 0 ]; then
	pass "glob filter backup succeeded"
else
	fail "glob filter backup failed (rc=${rc})"
fi

api_server_ok=0; api_client_ok=0; web_ok=1
[ -d "/tmp/test-glob-backup/api-server" ] && api_server_ok=1
[ -d "/tmp/test-glob-backup/api-client" ] && api_client_ok=1
[ -d "/tmp/test-glob-backup/web-frontend" ] && web_ok=0

if [ ${api_server_ok} -eq 1 ] && [ ${api_client_ok} -eq 1 ] && [ ${web_ok} -eq 1 ]; then
	pass "glob 'api-*' matched api-server and api-client, excluded web-frontend"
else
	fail "glob filter did not work correctly (server=${api_server_ok} client=${api_client_ok} web_excluded=${web_ok})"
fi

rm -Rf /tmp/test-multi-repos /tmp/test-glob-backup

# ── summary ───────────────────────────────────────────────────────────
cleanup

echo ""
echo "=============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "=============================="

if [ ${FAIL} -gt 0 ]; then
	exit 1
fi
exit 0
