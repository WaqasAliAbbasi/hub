# StudentBase cutover runbook

Phase 4 steps 5–7 of `PLAN.md`. Everything before this — compose file, secrets, workflow,
`prevent_destroy` — is already committed. This is the part with downtime in it.

Verified 2026-08-09, and the numbers below are why the plan says "move as-is":

| | |
|---|---|
| Old box | `188.166.206.48` (DO, sgp1), key `~/studentbase_private/id_rsa` |
| New box | `167.233.209.142` (hub), user `deploy`, 69 G free, 6.8 G RAM available |
| Postgres | `10.3 (Debian 10.3-1.pgdg90+1)` both sides — exact match, so no dump/restore |
| PGDATA | 110 MB, in the named volume `prisma-docker_postgres` |
| DNS | `studentbase.app` A, `api.studentbase.app` A, `www` is a **CNAME to the apex** |
| TTL | 1800 s on all records |

Two consequences worth reading before you start:

- **`www` follows the apex automatically.** Only two A records get flipped, not three.
- **The old Postgres and Redis containers have been up for three years** and have never been
  restarted. Step 3 is the first time they stop. That is a one-way door in practice: if
  10.3 declines to come back up on the old box, the copied PGDATA on hub is your only
  running copy. Take the backup in step 3 before stopping anything.

## 0. Prerequisites — done 2026-08-09

`HUB_SSH_HOST`, `HUB_SSH_KEY` and `SOPS_AGE_KEY` are set on **both**
`StudentBase/StudentBase` and `WaqasAliAbbasi/hub`.

Both CI credentials were rotated rather than recovered — the originals were not on the
laptop, since `make secrets-ci-init` prints the age key once and shreds it. What changed:

- New CI age recipient `age1l8nfu8a…`, replacing `age104gn5…`, in both `.sops.yaml` files.
  `projects/ynab-mcp/secrets.enc.env` and StudentBase's `secrets.enc.env` were re-encrypted
  with `sops updatekeys` and both verified to decrypt with the new key.
- New CI deploy key `ssh-ed25519 …+yzc hub-ci-deploy` in `ops/provision.sh`, installed on
  the box; the old one is removed from `deploy`'s `authorized_keys`.

Both changes are committed in this repo, so a rebuilt box provisions with the new key.
**hub's own workflows now depend on the rotated secrets too** — the next
`deploy-ynab-mcp.yml` or `deploy-freshrss.yml` run is the first real exercise of them.

Remaining before step 1: commit and push the StudentBase changes (compose.yml, .sops.yaml,
secrets.enc.env, secrets.enc.env.example, deploy-hub.yml, the Dockerfile healthcheck fix,
the redis.ts fix, .gitignore).

## 1. First deploy onto hub, with an empty database (no downtime)

Run `deploy-hub.yml` manually (`workflow_dispatch`). It builds the image to GHCR — the
first time hub's workflow has ever taken the `build: true` path — ships `compose.yml`, and
starts all three services. Postgres runs `initdb` and comes up empty. That is expected;
step 3 replaces it.

Three real bugs surfaced getting this far, all now fixed and worth knowing about if
anything here still looks wrong:

- **GHCR pull `unauthorized`.** A package pushed with the ephemeral `GITHUB_TOKEN`
  defaults to private, and the box had no credential to pull it — every other image in
  hub (FreshRSS, ynab-mcp) sidesteps this by being a pre-existing public image. Fixed in
  `deploy.yml`: the box `docker login`s to GHCR with the same token, over SSH, right
  before `docker compose pull`.
- **Postgres `initdb: could not look up effective user ID 1000`.** An earlier version of
  `compose.yml` pinned `user: "1000:1000"` on the postgres service, reasoning that the
  step-3 `tar` copy would land PGDATA as uid 1000. Wrong: `initdb` calls `getpwuid()` on
  that uid *before* the entrypoint can drop privileges, and the image's `/etc/passwd` has
  no such user. Fixed by removing the override — the image starts as root and chowns
  PGDATA to `postgres:postgres` itself, same as it always has on the droplet, regardless
  of what uid the bind-mount was owned by beforehand.
- **Traefik silently 404s everything, no logs, no errors.** The container was actually
  healthy at the process level — Apollo and Next.js both responding — but Docker reported
  it *unhealthy*, and Traefik's docker provider silently excludes unhealthy containers
  from routing (`docker logs platform-traefik-1` only shows this at `DBG` level as
  "Filtering unhealthy or starting container"; it never rises to INFO). The Dockerfile's
  own `HEALTHCHECK` was hitting `http://localhost:3000/...`, and under bridge networking
  on this box `localhost` resolves to `::1` first — which Next.js was never listening on,
  since `HOSTNAME=0.0.0.0` binds IPv4 only. It never surfaced on the droplet because that
  container ran with `--network=host`. Fixed in the Dockerfile: both healthcheck URLs now
  use `127.0.0.1`.

**The workflow's Verify step is meaningless here.** It polls `https://api.studentbase.app`,
which still resolves to the old droplet, so it will report success no matter what hub is
doing. Ignore it and verify by hand:

```sh
curl -k --resolve api.studentbase.app:443:167.233.209.142 https://api.studentbase.app/health
curl -k --resolve studentbase.app:443:167.233.209.142     https://studentbase.app/
```

`-k` is required and not a shortcut: Traefik cannot complete an ACME challenge for a
hostname whose DNS still points somewhere else, so it serves its own self-signed cert until
step 5. Expect failed certificate attempts in the Traefik log throughout — that is the
cost of verifying before flipping, and Let's Encrypt's failed-validation limit (5 per
hostname per hour) is high enough to absorb it as long as you do not sit in this state
churning for hours.

At this point the app should serve real pages against an empty database.

## 2. Detach DNS from Terraform, then drop the TTL (no downtime)

**`studentbase.app`'s DNS is Terraform-managed, not just sitting in a registrar.**
`digitalocean_record.prod_api` and `.prod_frontend`
(`deployment/terraform/environments/prod/domain_prod.tf`) both read
`value = module.server.ipv4_address` — the *old* droplet. Edit either record by hand while
Terraform still owns them, and the next `terraform apply` on this stack — for any unrelated
reason, before decommission — sees drift and silently flips DNS straight back to the dead
droplet. This is the same failure mode `prevent_destroy` was added to hub's server for,
just on the DNS side.

Detach them from state first, so they become unmanaged and nothing can revert them:

```sh
cd deployment/terraform/environments/prod
terraform state rm digitalocean_record.prod_api digitalocean_record.prod_frontend
```

This needs the same DO token and Spaces-backed state access as any other `terraform`
command here — neither is on this laptop; source them the way `terraform apply` normally
does. `www` needs no action: it is a CNAME to `@` and was never pointed at an IP.

`doctl` is not installed locally — install it, or use the DO web console. Either way, only
after the `state rm` above:

```sh
doctl compute domain records list studentbase.app
# set ttl to 60 on the two A records: @ (prod_frontend) and api (prod_api)
```

Wait **30 minutes** — one old TTL — for resolvers to pick the shorter value up. The plan
originally said "a day ahead"; at a 1800 s starting TTL that is unnecessary.

At step 7 (decommission), delete `domain_prod.tf`'s two resources from code entirely —
they are already out of state, so this just stops them showing up as an addition on some
future `terraform plan`. The plan's "keep the DNS records" still holds: this only removes
Terraform's management of them, not the records themselves.

## 3. Copy the data (downtime begins)

Back up first, while the old stack is still healthy:

```sh
ssh -i ~/studentbase_private/id_rsa root@188.166.206.48 \
  'docker exec prisma-docker_postgres_1 pg_dumpall -U prisma' > studentbase-predump.sql
```

Stop the old app and database so nothing writes during the copy:

```sh
ssh -i ~/studentbase_private/id_rsa root@188.166.206.48 \
  'docker stop studentbase-web prisma-docker_postgres_1'
```

Clear the `initdb` data and stream the real PGDATA across. It lands owned by `deploy`
(uid 1000) — `tar` run as a non-root user can't preserve the source's uid 999 — but that is
fine and needs no `user:` override on the postgres service: the container starts as root by
default and its entrypoint `chown -R`s PGDATA to postgres:postgres (999:999) itself before
dropping privileges, the same as it always has on the droplet. An earlier version of
`compose.yml` pinned `user: "1000:1000"` to try to pre-empt this and broke first boot
instead — `initdb` calls `getpwuid()` on that uid before the entrypoint can drop privileges,
and the image's `/etc/passwd` has no entry for 1000, only for `postgres`.

```sh
ssh deploy@167.233.209.142 \
  'docker compose -f /srv/studentbase/compose.yml stop postgres && \
   rm -rf /srv/studentbase/data/postgres && mkdir -p /srv/studentbase/data/postgres'

ssh -i ~/studentbase_private/id_rsa root@188.166.206.48 \
  'tar -C /var/lib/docker/volumes/prisma-docker_postgres/_data -cf - .' \
| ssh deploy@167.233.209.142 \
  'tar -C /srv/studentbase/data/postgres -xf -'
```

Bring it back up and confirm Postgres accepted the copied directory:

```sh
ssh deploy@167.233.209.142 \
  'cd /srv/studentbase && docker compose up -d && sleep 10 && docker compose logs postgres | tail -20'
```

## 4. Verify against the new box before anyone else sees it

```sh
curl -k --resolve api.studentbase.app:443:167.233.209.142 https://api.studentbase.app/health
curl -k --resolve studentbase.app:443:167.233.209.142     https://studentbase.app/
```

Then a real login through a browser with the same two entries in `/etc/hosts`. A login
exercises Postgres reads, JWT signing and Redis writes in one action, which is the point.
Redis is empty by design — anything session-like will have been dropped, so expect to log
in fresh.

## 5. Flip DNS — done 2026-08-09

Both A records point at `167.233.209.142`. `www` follows the apex CNAME, unaffected.

Skipped the 30-minute TTL wait from step 2 by choice — traded a slower, staggered
propagation (some resolvers, including Let's Encrypt's own, briefly still routed to the
stopped old droplet and got ACME `502`s) for not waiting. Traefik retries ACME
automatically; no action was needed once DNS actually converged.

Row counts verified equal (6390) between the pre-cutover `pg_dumpall` and the live database
on hub before the flip — see step 4. The backup dump is at
`/tmp/claude-*/scratchpad/studentbase-predump.sql` on the laptop that ran the cutover; move
it somewhere durable if it's worth keeping past this session, since scratchpads are
ephemeral.

## 6. Leave the old droplet powered off for a week — not yet done

Still running, docker containers stopped (`studentbase-web`, `prisma-docker_postgres_1`),
droplet itself untouched. Its PGDATA is read-only from this point on — nothing has written
to it since the tar copy in step 3 — so it remains a faithful rollback target regardless of
when it's actually powered off.

```sh
ssh -i ~/studentbase_private/id_rsa root@188.166.206.48 'shutdown -h now'
```

Powered off, **not destroyed**, and not `terraform destroy` — that would take the Spaces
bucket and DNS records with it.

## 7. Decommission — partially done early, 2026-08-09

Done ahead of the week-long hold, once the cutover itself was verified (row counts, live
health checks) rather than waiting on the droplet purely as a time-based ritual:

- `deployment/terraform/modules/web`, `modules/server`, and `environments/prod/server.tf` /
  `docker.tf` / `domain_prod.tf` are deleted. `terraform state rm module.server module.web`
  first — non-destructive, the droplet and its data are untouched; this only stops
  StudentBase's Terraform from tracking them. `terraform plan` came back clean afterward:
  zero drift on everything that survives (Spaces, the CDN, its certificate, mail/spf/icloud
  records).
- `prod_api` / `prod_frontend` — the two IP-bearing DNS records, already detached from
  StudentBase's state in step 2 — are **defined and imported in hub's own Terraform**,
  `terraform/dns-studentbase.tf`, pointing at `hcloud_server.hub.ipv4_address`. A
  `terraform apply` in *hub* is what can now change where `studentbase.app` resolves;
  StudentBase's Terraform no longer has an opinion.

**Extended further than the original plan, 2026-08-09: all of StudentBase's remaining
Terraform — not just the droplet/web modules — is now gone, and everything it managed is
either imported into hub's Terraform or freshly recreated there.** `deployment/terraform/`
is deleted entirely (was: `acme.tf`, `domain.tf`, `domain_for_tools.tf`, `mail.tf`,
`spaces.tf`, plus `main.tf`/`variables.tf`/`outputs.tf`/`versions.tf`). All 17 remaining
resources were `terraform state rm`'d from StudentBase first — non-destructive, same
pattern as the droplet — leaving StudentBase's state completely empty. `terraform.tfvars`
was gitignored and had no git history, so it's gone from disk with the rest of the
directory; confirmed with the user that the DO token and Spaces keys it held exist
elsewhere (password manager / DO dashboard), nothing lost.

What moved into hub's `terraform/studentbase-cdn.tf` (new providers `acme`/`tls` added to
`main.tf` to support it):

- Both Spaces buckets (`sb-cdn-prod`, `sb-prod-backup`), the CDN, and every remaining DNS
  record (`www`, `content`, SPF, DKIM, DMARC, the two Postmark records, both icloud MX
  entries) — all cleanly `terraform import`-able, real existing objects, IDs recorded in
  that file's header comment.
- The certificate chain (`tls_private_key` → `acme_registration` → `acme_certificate` →
  `digitalocean_certificate`) is **not** imported — the `acme` provider can't reconstruct a
  private key or a certificate from just an ID, there's no "read my key back" ACME
  operation. It's freshly recreated instead: a new ACME account, a new DNS-01 challenge
  against the same DigitalOcean account (already proven able to manage `studentbase.app`,
  via the DNS A-record import), a new cert covering the same SANs the old one did. Free, and
  the CDN's `certificate_name` updates in place with no downtime — DO doesn't require
  recreating a CDN to swap its cert.
- The old DO certificate object (`LetsEncryptTerraform8a0ff1bb`, ID
  `7d8c0447-f374-4db6-81c9-4f49cf5f5baf`) is left alone for now — it can't be deleted while
  the CDN still references it. Delete it by hand, once the CDN is confirmed serving on the
  new cert.
- Dead variables removed from `variables.tf` before the file itself was deleted: everything
  that only fed the droplet/container (`pub_key`, `pvt_key`, `docker_username`,
  `docker_password`, `docker_image`, `contact_email_address`, `postmark_api_key`,
  `facebook_app_*`, `google_*`), plus `environment` and `prisma_service` (the latter was
  already dead before this reorg — unused anywhere in the tree).

Still needs, once hub's DigitalOcean token is loaded (not available on the machine that did
this reorg): run every `terraform import` in `dns-studentbase.tf` and
`studentbase-cdn.tf`'s header comments, in the order given, then `terraform plan` — it
should show only the three new cert resources being created and the CDN's
`certificate_name` updating in place. Anything else means an import targeted the wrong
object.

Also done: `deploy.yaml` (the monthly-cron Terraform deploy) is deleted, `backup_db.yml`
(already broken — it read a `terraform output` this reorg removed, and SSHed into the now-
stopped droplet) is deleted, and `deploy-hub.yml` is renamed to `deploy.yml` with
`push: branches: [main]` — deploys are push-triggered again, this time actually landing on
hub. Note: `backup_db.yml` and the old `deploy.yaml` were the only consumers of several
StudentBase repo secrets (`SSH_KEY`, `SSH_CONFIG`, `DO_SPACES_ACCESS_ID`,
`DO_SPACES_SECRET_KEY`, `DO_SPACES_BACKUP_BUCKET`) — those are now unused and worth
deleting from the repo's secrets settings, though nothing breaks by leaving them.

Decided, not open: the credentials copied in Phase 4 stay as-is, not rotated. Moved
verbatim from the droplet's `/env`; `secrets.enc.env.example` still records which ones bite
if this is ever revisited (`JWT_SECRET` logs everyone out, `EMAIL_VERIFICATION_SECRET`
invalidates any link already in someone's inbox).

## Rollback

**Before step 5:** was free — nothing pointed at hub.

**After step 5, before this reorg:** point the two A records back at `188.166.206.48` via
the DO API/console and start the old droplet.

**After this reorg:** the same manual DNS flip works, but it now fights *hub's* Terraform
instead of StudentBase's — the exact footgun step 2 first guarded against, just moved. A
manually-edited record left in place across an unrelated `terraform apply` on hub gets
silently reverted back to the hub IP, because `dns-studentbase.tf` still declares it that
way. If a real rollback is ever needed, run `terraform state rm
digitalocean_record.studentbase_api digitalocean_record.studentbase_apex` in hub's
Terraform *before* flipping the records by hand, exactly as step 2 did to StudentBase's
state during the cutover itself.

Either way, the old droplet's PGDATA is untouched by the copy — read-only on that side — so
it comes back exactly as it was, minus any writes that landed on hub in between.
