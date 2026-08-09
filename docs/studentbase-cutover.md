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
secrets.enc.env, secrets.enc.env.example, deploy-hub.yml, the redis.ts fix, .gitignore).

## 1. First deploy onto hub, with an empty database (no downtime)

Run `deploy-hub.yml` manually (`workflow_dispatch`). It builds the image to GHCR — the
first time hub's workflow has ever taken the `build: true` path — ships `compose.yml`, and
starts all three services. Postgres runs `initdb` and comes up empty. That is expected;
step 3 replaces it.

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

Clear the `initdb` data and stream the real PGDATA across. Unpacking **as `deploy`** is
load-bearing: `deploy` has no sudo and cannot `chown` to Postgres's usual uid 999, so the
files land as uid 1000 — which is exactly why `compose.yml` pins the service to
`user: "1000:1000"`. `tar` preserves the 0700 mode Postgres also insists on.

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

## 5. Flip DNS (downtime ends)

Point both A records at `167.233.209.142`. `www` follows the apex CNAME.

Watch the certificates arrive — this is the first moment ACME can actually succeed:

```sh
ssh deploy@167.233.209.142 'docker logs -f platform-traefik-1'
curl -sI https://studentbase.app | head -1
curl -sI https://api.studentbase.app | head -1
```

Restore the TTL to 1800 once traffic looks right.

## 6. Leave the old droplet powered off for a week

```sh
ssh -i ~/studentbase_private/id_rsa root@188.166.206.48 'shutdown -h now'
```

Powered off, **not destroyed**, and not `terraform destroy` — that would take the Spaces
bucket and DNS records with it.

## 7. Decommission (after the week)

- Delete `deployment/terraform/modules/web`, `modules/server`, and every SSH provisioner.
- Delete `.github/workflows/deploy.yaml` (the monthly-cron Terraform deploy), then rename
  `deploy-hub.yml` to `deploy.yml` and give it `push: branches: [main]`.
- Keep Spaces, the CDN, and the DNS records.
- Rotate the credentials copied in Phase 4 — they were moved as-is, and
  `secrets.enc.env.example` records which ones bite (`JWT_SECRET` logs everyone out).

## Rollback

Before step 5, rollback is free: nothing points at hub. After step 5, point the two A
records back at `188.166.206.48` and start the old droplet; at TTL 60 it is a couple of
minutes. The old PGDATA is untouched by the copy — it is read-only on that side — so the
old box comes back exactly as it was, minus any writes that landed on hub in between.
