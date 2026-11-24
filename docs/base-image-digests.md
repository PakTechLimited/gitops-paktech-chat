# Base image digests (postgres and redis)

The app images (api and web) are rebuilt by the pipeline and written to the environment
values by digest after every build. The **postgres and redis images are not**: they are
pinned once, by digest, in `charts/paktech-chat/values.yaml` and stay frozen until someone
moves them. A digest pin keeps deploys reproducible, but it also means security fixes only
arrive when we choose to take them.

There are no per-environment overrides, so a change to the base values reaches dev, staging
and prod. Dev and staging sync automatically; prod waits for the manual sync.

## When to check

- Once a month, and before a release that matters.
- Whenever Trivy Operator or the Trivy dashboard shows a HIGH or CRITICAL finding in the
  postgres or redis image.

## Procedure

1. Compare the pinned digests with today's:

        bash scripts/base-image-digests.sh

   `up to date` means nothing to do. `NEWER DIGEST AVAILABLE` means the tag now points to a
   different image (usually a patch release or a rebuilt base layer).

2. Scan the new digest before adopting it (take the digest from the `current:` line):

        docker run --rm aquasec/trivy image --severity HIGH,CRITICAL postgres:16-alpine@sha256:<new>

   Do not take a digest with more critical findings than the one in use.

3. Try it in dev first. Add a temporary override in `environments/dev/values.yaml`:

        postgres:
          image: postgres:16-alpine@sha256:<new>

   Open a pull request. `scripts/render-check.sh` runs on it and rejects an image that is not
   pinned by digest. After the merge, dev syncs: the postgres pod restarts (its data is on the
   persistent volume), the migrate Job shows `Init:0/1` and then `Completed`, and the api
   becomes Ready again. Check the Trivy dashboard for the new findings.

4. Move it to the base values. Change the digest in `charts/paktech-chat/values.yaml`, delete
   the dev override, open a pull request. Staging syncs by itself. For prod, read the diff of
   the sync and run the manual sync.

5. Record the old and new digest and the scan result in the pull request description.

## Rollback

Revert the pull request. Data stays on the persistent volume. Moving between patch releases
of the same major version is safe in both directions.

## Out of scope

A major version change (for example postgres 16 to 17) is not a digest bump. It needs a dump
and restore or `pg_upgrade`, planned separately.

## Worked examples

### 2026-11-24: newer digest, same scan, no bump

`scripts/base-image-digests.sh` reported a newer digest for `postgres:16-alpine`
(`f2f98726...`, pinned `1d5b02d3...`). Trivy (HIGH and CRITICAL) gave identical
results for both: alpine 3.24.4, 26 HIGH, 1 CRITICAL, same packages (libxml2 and the
Go stdlib in gosu). Decision: keep the pin. A bump would restart PostgreSQL in all three
environments for no security gain. Revisit when a digest scans better.

### 2026-11-24: proving the migrate Job waits for PostgreSQL

On dev, the migrate Job was deleted and the PostgreSQL StatefulSet restarted at the same
time, then Argo CD was synced. The migrate pod stayed in `Init:0/1` for about 23 seconds
(the `wait-for-postgres` init container), then went PodInitializing, Running and
Completed in 45 seconds, with no restarts and no failed attempts.
