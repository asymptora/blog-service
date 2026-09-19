# Restore the Ghost Database from a Backup

**Trigger:** verifying that the nightly `mysqldump` backup is actually
usable, or recovering the Ghost database after data loss.

**Prerequisites:** SSH access to the Ghost LXC (`ghost-blog` alias, CTID
105 on `pve1`), Docker running there, a dump file at
`/opt/ghost/backups/ghost-db.sql.gz`, and `/opt/ghost/.env` present if
comparing against the live production database.

**Owner:** Higor Cazuza.

## Steps

1. **Start a disposable MySQL container**

   Command:

   ```
   docker run -d --rm --name mysql-restore-test \
     -e MYSQL_ROOT_PASSWORD=scratch_test_password \
     mysql:8.0.44@sha256:f37951fc3753a6a22d6c7bf6978c5e5fefcf6f31814d98c582524f98eae52b21

   until docker exec mysql-restore-test mysqladmin ping -uroot -pscratch_test_password -h 127.0.0.1 --silent 2>/dev/null; do
     echo "waiting for mysql to come up..."
     sleep 1
   done
   ```

   Expected output:

   ```
   mysqld is alive
   ```

   No `--network` flag: this lands on Docker's default `bridge` network,
   separate from the production `ghost_network`, so there is no path by
   which this container could reach or be reached by the real database.

2. **Create the target database**

   `mysqldump` without `--databases` does not write a `CREATE DATABASE`
   statement into the dump, so the destination has to exist first.

   Command:

   ```
   docker exec mysql-restore-test mysql -uroot -pscratch_test_password -e "CREATE DATABASE ghost;"
   ```

   Expected output: none (silent on success).

3. **Restore the dump**

   Command:

   ```
   gunzip -c /opt/ghost/backups/ghost-db.sql.gz | docker exec -i mysql-restore-test mysql -uroot -pscratch_test_password ghost
   ```

   Expected output: none (silent on success). A non-zero exit code or
   any `ERROR` line means the dump did not import cleanly; see "If it
   fails" below.

4. **Compare row counts against production**

   Command:

   ```
   set -a; source /opt/ghost/.env; set +a

   for t in posts users settings tags; do
     prod=$(docker exec ghost-db-1 mysql -uroot -p"$DATABASE_ROOT_PASSWORD" -N -e "SELECT COUNT(*) FROM $t;" ghost 2>/dev/null)
     scratch=$(docker exec mysql-restore-test mysql -uroot -pscratch_test_password -N -e "SELECT COUNT(*) FROM $t;" ghost 2>/dev/null)
     echo "$t: production=$prod restored=$scratch"
   done
   ```

   Expected output:

   ```
   posts: production=N restored=N
   users: production=N restored=N
   settings: production=N restored=N
   tags: production=N restored=N
   ```

   Every line's two numbers matching. `N` varies over time as the blog
   gets real content; what matters is that both sides of each line agree
   with each other, not any specific value.

5. **Spot-check actual content, not just row counts**

   Matching counts with mismatched rows is possible in principle, so
   confirm the content itself agrees on at least one table.

   Command:

   ```
   docker exec ghost-db-1 mysql -uroot -p"$DATABASE_ROOT_PASSWORD" -N -e "SELECT id, title FROM posts ORDER BY id;" ghost
   docker exec mysql-restore-test mysql -uroot -pscratch_test_password -N -e "SELECT id, title FROM posts ORDER BY id;" ghost
   ```

   Expected output: the two result sets are identical, same `id`, same
   `title`, same order.

6. **Tear down the disposable container**

   Command:

   ```
   docker stop mysql-restore-test
   ```

   Expected output: the container name printed once, confirming it
   stopped. `--rm` at creation means it is removed automatically; nothing
   else to clean up.

## If it fails

- Step 1 never reaches `mysqld is alive`: the scratch container failed
  to start. Check `docker logs mysql-restore-test`.
- Step 3 errors or exits non-zero: the dump file is corrupted or
  truncated. Check its integrity with `gunzip -t /opt/ghost/backups/ghost-db.sql.gz`
  before assuming the backup itself is bad; a truncated copy during
  transfer looks identical to a truncated original otherwise.
- Step 4 counts disagree: re-run `systemctl start ghost-backup.service`
  to produce a fresh dump and repeat this runbook from step 1 before
  concluding the backup mechanism itself is broken; a stale dump from
  before recent content changes will legitimately show lower counts.
- Step 5 shows matching counts but different rows: stop here and
  investigate immediately. This would mean the dump or restore silently
  altered data, a more serious problem than a simple count mismatch.

## References

- RFC-0001 (docs/rfcs/0001-ghost-blog-production-deployment.md), section
  "Backups"
- scripts/backup-db.sh
- Issue #9 (backup script), #10 (this verification)
