#!/bin/sh
#
# Regression tests for the git backup/restore scripts.
#
# These cases reproduce the failures that only show up outside the demo
# "happy path": paths containing spaces, missing bundles, partially restored
# targets, bundle ordering across several incremental bundles, over-eager tag
# matching, and repositories that are not on the expected branch.
#
# Each case is independent and asserts both the exit code and the (categorised)
# error message. The script exits non-zero if any assertion fails.
#

# Resolve the location of the scripts under test (absolute, space-safe).
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
SRC=$(cd "${SCRIPT_DIR}/../src" && pwd -P)
SEED_BUNDLE="${SCRIPT_DIR}/repo.bundle"
BACKUP="${SRC}/backup-git.sh"
RESTORE="${SRC}/backup-git-restore.sh"

# Hermetic git identity so commits work regardless of the host configuration.
export GIT_AUTHOR_NAME="regress"
export GIT_AUTHOR_EMAIL="regress@example.com"
export GIT_COMMITTER_NAME="regress"
export GIT_COMMITTER_EMAIL="regress@example.com"

# A workspace whose path *contains a space*, so every sub-path exercises the
# quoting fixes automatically.
WORK=$(mktemp -d "${TMPDIR:-/tmp}/git backup regress.XXXXXX") || {
	echo "FATAL: cannot create temp workspace" >&2
	exit 1
}
trap 'rm -rf "${WORK}"' EXIT INT TERM

failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

# contains <haystack> <needle> -> success if needle is a substring of haystack
contains() {
	case "$1" in
		*"$2"*) return 0 ;;
		*) return 1 ;;
	esac
}

commit_change() {
	# commit_change <repo_dir> <text>
	echo "$2" >> "$1/data.txt"
	git -C "$1" add data.txt
	git -C "$1" commit -q -m "$2"
}

echo "workspace: ${WORK}"

# ---------------------------------------------------------------------------
# Case 1: full round-trip with spaces in every path + multiple bundles (ordering)
# ---------------------------------------------------------------------------
srcParent="${WORK}/src repos"
repo="${srcParent}/my repo"
backupDir="${WORK}/backup dir"
restoreParent="${WORK}/restore dir"
mkdir -p "${srcParent}" "${backupDir}"

git clone -q "${SEED_BUNDLE}" "${repo}"

# initial backup (full bundle) + two incremental backups with distinct commits
"${BACKUP}" "${srcParent}" "${backupDir}" >/dev/null 2>&1
sleep 1
commit_change "${repo}" "regress-step-1"
"${BACKUP}" "${srcParent}" "${backupDir}" >/dev/null 2>&1
sleep 1
commit_change "${repo}" "regress-final-marker"
"${BACKUP}" "${srcParent}" "${backupDir}" >/dev/null 2>&1

# how many bundles were produced (need >= 2 to meaningfully test ordering)
bundleCount=$(find "${backupDir}" -maxdepth 1 -name 'my repo_*.bundle' | wc -l)

out=$( cd "${backupDir}" && "${RESTORE}" "${restoreParent}" "my repo" 2>&1 )
rc=$?

restored="${restoreParent}/my repo"
if [ "${rc}" -eq 0 ] && [ -d "${restored}/.git" ]; then
	pass "case1: round-trip with spaces in paths succeeds"
else
	fail "case1: round-trip with spaces failed (rc=${rc})"
	printf '%s\n' "${out}" | sed 's/^/      | /'
fi

if [ "${bundleCount}" -ge 2 ]; then
	pass "case1: produced ${bundleCount} bundles (ordering exercised)"
else
	fail "case1: expected >=2 bundles, got ${bundleCount}"
fi

if git -C "${restored}" log --oneline 2>/dev/null | grep -q "regress-final-marker"; then
	pass "case1: bundles applied in order (final commit present)"
else
	fail "case1: final commit missing -> bundles applied out of order"
fi

# ---------------------------------------------------------------------------
# Case 2: no bundle matches the repository name
# ---------------------------------------------------------------------------
emptyBackups="${WORK}/empty backups"
mkdir -p "${emptyBackups}"

out=$( cd "${emptyBackups}" && "${RESTORE}" "${WORK}/restore ghost" "ghostrepo" 2>&1 )
rc=$?

if [ "${rc}" -ne 0 ] && contains "${out}" "no bundle files matching"; then
	pass "case2: missing bundles -> clear [path] error, non-zero exit"
else
	fail "case2: missing-bundle case not handled (rc=${rc})"
	printf '%s\n' "${out}" | sed 's/^/      | /'
fi

# ---------------------------------------------------------------------------
# Case 3: restore target already exists but is not a git repository
# ---------------------------------------------------------------------------
badParent="${WORK}/bad target"
mkdir -p "${badParent}/my repo"
echo "stale" > "${badParent}/my repo/leftover.txt"

out=$( cd "${backupDir}" && "${RESTORE}" "${badParent}" "my repo" 2>&1 )
rc=$?

if [ "${rc}" -ne 0 ] && contains "${out}" "not a valid git repository"; then
	pass "case3: incomplete restore target -> clear [git] error, non-zero exit"
else
	fail "case3: incomplete-target case not handled (rc=${rc})"
	printf '%s\n' "${out}" | sed 's/^/      | /'
fi

# ---------------------------------------------------------------------------
# Case 4: a decoy tag whose name *contains* the backup tag must not fool the
#         "has a previous backup?" check (old grep -c substring bug).
# ---------------------------------------------------------------------------
tagParent="${WORK}/tag repos"
tagRepo="${tagParent}/tagrepo"
tagBackup="${WORK}/tag backup"
mkdir -p "${tagParent}" "${tagBackup}"
git clone -q "${SEED_BUNDLE}" "${tagRepo}"
# decoy tag, NO real "lastBackup" tag exists yet
git -C "${tagRepo}" tag "notlastBackup"

out=$( "${BACKUP}" "${tagParent}" "${tagBackup}" 2>&1 )
rc=$?

createdBundle=$(find "${tagBackup}" -maxdepth 1 -name 'tagrepo_*.bundle' | wc -l)
if [ "${rc}" -eq 0 ] && [ "${createdBundle}" -ge 1 ] \
	&& git -C "${tagRepo}" rev-parse -q --verify "refs/tags/lastBackup" >/dev/null; then
	pass "case4: decoy tag ignored, initial backup created correctly"
else
	fail "case4: substring tag matching broke the backup (rc=${rc}, bundles=${createdBundle})"
	printf '%s\n' "${out}" | sed 's/^/      | /'
fi

# ---------------------------------------------------------------------------
# Case 5: repository without the expected 'master' branch is skipped with a
#         clear, categorised error instead of an obscure git failure.
# ---------------------------------------------------------------------------
noMasterParent="${WORK}/no master"
noMasterRepo="${noMasterParent}/proj"
noMasterBackup="${WORK}/no master backup"
mkdir -p "${noMasterRepo}" "${noMasterBackup}"
git -C "${noMasterRepo}" init -q -b main
echo "x" > "${noMasterRepo}/f.txt"
git -C "${noMasterRepo}" add f.txt
git -C "${noMasterRepo}" commit -q -m "on main"

out=$( "${BACKUP}" "${noMasterParent}" "${noMasterBackup}" 2>&1 )
rc=$?

if [ "${rc}" -ne 0 ] && contains "${out}" "branch 'master' not found"; then
	pass "case5: missing 'master' branch -> clear [git] error, non-zero exit"
else
	fail "case5: missing-branch case not handled (rc=${rc})"
	printf '%s\n' "${out}" | sed 's/^/      | /'
fi

# ---------------------------------------------------------------------------
echo
if [ "${failures}" -eq 0 ]; then
	echo "regression: all cases passed"
	exit 0
else
	echo "regression: ${failures} case(s) failed"
	exit 1
fi
