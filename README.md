git-backup
==========
Simple shell scripts for creating and restoring incremental backups of git repositories using git bundles.

The backup routine tags the last backed-up commit with `lastBackup` and uses
`git bundle create --all lastBackup..master` to create incremental bundles.
Only the `master` branch is backed up; repositories that do not have a `master`
branch are skipped with a clear error (and do not abort backups of other repos).
After restoring the backup only the `master` branch will be restored.

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

If the backup directory is omitted it defaults to `~/backup`.
Repository and backup paths may contain spaces.

Restore
----------
In order to restore a repository named `repository` into `/tmp/git/repository`,
run the restore script from the directory containing `repository_*.bundle` files:

```
backup-git-restore.sh /tmp/git repository
```

The directory must contain the complete set of `repository_*.bundle` files: they are
applied oldest-first (by the timestamp embedded in their names), so an empty directory
or a missing initial bundle makes the restore fail with a clear error.

Testing
----------
The simplified test suite clones a repository from a bundle file, 
simulates a few commits and runs the backup after every single commit.

Afterwards the repository is restored from multiple bundle files.

The suite also runs regression tests (`test-regression.sh`) covering paths with
spaces, missing bundles, partial restore targets, bundle ordering and tag matching.

```
cd test
./run.sh
```

