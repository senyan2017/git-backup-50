git-backup
==========
Simple shell scripts for creating and restoring incremental backups of git repositories using git bundles.

The backup routine uses `git bundle create --all lastBackup..<current-branch>` to create incremental bundles.
The current branch is detected automatically via `HEAD` (no longer hardcoded to `master`).

Backup
----------
Create a backup of a single repository and save it into `/backup`:
```
backup-git.sh /path/to/repository /backup
```

Create backups of multiple repositories located in `~/projects` and save them into `/backup`:
```
backup-git.sh ~/projects /backup
```

Paths with spaces and special characters are supported — just quote them as usual:
```
backup-git.sh "/path/to/my projects" "/my backup dir"
```

Restore
----------
Restore a repository named `repository` into `/tmp/git/repository` from bundle files
located in the current directory:

```
backup-git-restore.sh /tmp/git repository
```

Or specify the bundle directory explicitly (recommended):

```
backup-git-restore.sh /tmp/git repository /path/to/bundles
```

If no matching bundle files are found, the script exits with an error instead of silently doing nothing.

Testing
----------
The test suite covers:

* Basic incremental backup and restore
* Paths containing spaces and special characters
* Missing bundle files (graceful error)
* Invalid source/destination directories
* Partially existing restore targets
* Usage messages on missing arguments

```
cd test
./run.sh
```
