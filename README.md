git-backup
==========
Simple shell scripts for creating and restoring incremental backups of git repositories using git bundles.

The backup routine uses git `bundle create --all last_backup_tag..master` to create incremental bundles.
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

Restore
----------
In order to restore a repository named `repository` into `/tmp/git/repository`,
run the restore script from the directory containing `repository_*.bundle` files:

```
backup-git-restore.sh /tmp/git repository
```

Testing
----------
The test suite runs two clearly separated phases so a failure points at the
side that broke:

* **backup phase** – clone a repository from a bundle file, then repeatedly
  commit a change and create an incremental bundle (exercises `backup-git.sh`).
* **restore phase** – rebuild the repository from those bundles into
  `/tmp/git` (exercises `backup-git-restore.sh`).

It prints `OK`/`ERROR` and exits non-zero if either phase fails.

```
cd test
./run.sh
```

Layout
----------
* `src/backup-git.sh`, `src/backup-git-restore.sh` – the backup and restore CLIs.
* `src/lib-git-backup.sh` – shared logging / error-handling / precondition helpers, sourced by both scripts.
* `test/run.sh` – the two-phase test runner; `test/test-*.sh` are its steps and `test/lib-test.sh` holds shared test helpers.

