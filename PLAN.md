# Hub: plan to become the home for all side projects

Goal: one cheap box hosting several side projects, where adding a project means writing a
compose file and a DNS-free subdomain label — not editing another project's
infrastructure code. Plus enough monitoring to know when something breaks without SSHing in.

Status as of 2026-08-09: `hub` is **live** on Hetzner (fsn1), wildcard DNS resolves,
Traefik is issuing real Let's Encrypt certs, and Dozzle is up behind basic-auth. `waqasali.dev`
apex stays on GitHub Pages. StudentBase is still on its own DO droplet at `188.166.206.48`,
untouched. Phase 3 is proven: the reusable GitHub Actions deploy workflow shipped FreshRSS
to `/srv/freshrss` over CI, Traefik issued a real cert for `read.waqasali.dev` with no
manual step, and its data lands at `/srv/freshrss/data` where the nightly backup picks it
up automatically. A second project — `projects/ynab-mcp/` — has since gone out the same
way, adding per-project sops secrets to the deploy workflow, and
`docs/disaster-recovery.md` documents rebuilding the box from backups.

The server now carries `prevent_destroy` (see Phase 4), so Terraform errors rather than
rebuilds.

**Decisions made:** Docker Compose + Traefik (not K3s). Hetzner, region flexible.
No HA. StudentBase migrates here once the platform is proven. Uptime Kuma and Beszel were
evaluated and deliberately skipped for now — see Phase 2 below.

---

## 1. StudentBase (to absorb in Phase 4)

One `s-1vcpu-2gb` droplet in `sgp1`: host nginx terminating TLS, one container running
both Next.js (`:3000`) and Apollo (`:8080`) under tini, plus a host-level compose stack
with `postgres:10.3` and `redis:alpine`. Deploys are a monthly-cron GitHub Action ending
in `terraform apply` with 17 `-var` flags, which SSHes in and `docker run`s the new image.

Why it can't currently share a box:

- TLS SANs are a hardcoded list in `acme.tf`, renewed only when Terraform runs — monthly,
  against 90-day certs.
- nginx config is one static file, `files/api.studentbase.app`, holding every server block.
- Deploy and infra provisioning are the same operation.
- `ubuntu-18.04` (EOL 2023) and `postgres:10.3` (EOL 2022) — needs rebuilding regardless.
- Live credentials in plaintext in `deployment/terraform/environments/prod/terraform.tfvars`
  (DO token, Docker Hub password, Postmark key, Facebook secret, GCP key), duplicated into
  `/env` on the droplet. Gitignored and never committed, but they need rotating.

---

## 2. Architecture

```
Hetzner CX33 (4 vCPU / 8 GB, fsn1)
│
├── /srv/platform/
│   ├── traefik/      :80 :443 — routes by Docker label, auto Let's Encrypt
│   └── dozzle/       logs.waqasali.dev    — logs for every container, basic-auth
│
├── /srv/studentbase/ compose.yml + .env + data/   (Phase 4)
├── /srv/freshrss/    compose.yml + data/
├── /srv/ynab-mcp/    compose.yml + .env + data/
└── /srv/<next>/      ...
```

Adding a project is a directory under `/srv` and three labels:

```yaml
services:
  web:
    image: ghcr.io/waqasaliabbasi/project-two:sha-abc1234
    restart: always
    labels:
      - traefik.enable=true
      - traefik.http.routers.p2.rule=Host(`p2.waqasali.dev`)
      - traefik.http.routers.p2.tls.certresolver=le
    networks: [edge, default]
networks:
  edge:
    external: true
```

Traefik requests, installs and renews the cert itself. With a wildcard DNS record already
in place, no DNS change is needed either. Nothing in `hub` changes.

### Division of responsibility

- **Terraform (this repo)** owns the server, firewall, DNS, and Spaces. Runs rarely, from
  your laptop.
- **`stacks/` (this repo)** owns platform services. Deployed by a workflow here.
- **Each app's own repo** owns its `compose.yml` and its deploy workflow. This is the
  change that stops "add a project" from meaning "edit hub" — and it's precisely the
  coupling that makes StudentBase painful today.

### Deploy mechanism

Per app repo: build → push to **GHCR** → SSH → `docker compose pull && docker compose up -d`.

GHCR rather than Docker Hub means no registry password in Terraform or on the box — a
scoped token does it. CI connects as a dedicated `deploy` user in the `docker` group,
holding a key that is not your personal one.

Deliberately not Dokploy/Coolify: they'd wrap exactly this stack in a UI, but add a
stateful control plane that owns your infra and has its own upgrade path and failure
modes. ~40 lines of compose you fully understand is the better trade at this size. Revisit
if managing six `/srv` directories starts to chafe.

---

## 3. Sizing

| Workload | Reserved |
|---|---|
| Docker daemon + Traefik | ~0.2 GB |
| StudentBase web + api | ~1.0 GB |
| Postgres (10.3 at cutover, 17 after Phase 5) | ~0.4 GB |
| Redis (already capped `maxmemory 150mb`) | ~0.2 GB |
| Dozzle | ~0.05 GB |
| FreshRSS | ~0.3 GB |
| ynab-mcp | ~0.15 GB |
| **Subtotal** | **~2.3 GB** |

**CX33** (4 vCPU / 8 GB, ~€8/mo — Hetzner's successor to the retired CX32, same memory,
more cores) is what's deployed — image builds, Postgres restores and traffic spikes all
want headroom, and headroom is what makes "deploy more side projects" actually true
rather than aspirational.

**CX22** (2 vCPU / 4 GB, ~€4.35/mo) now genuinely fits, which it did not under K3s. Take
it if you want the floor price; ~1.5 GB spare is enough until roughly the third project.

Verify current Hetzner pricing at order time — they raised cloud prices in April and again
in June 2026.

End-state cost: **~€8 + $5 Spaces ≈ $14/mo** for everything, versus **$17/mo** today for
StudentBase alone.

**Latency note:** you've said the region need not be Singapore, so EU it is — but that does
add ~150-200 ms for any Asian StudentBase users. Putting Cloudflare in front of
`studentbase.app` (free tier) caches static assets at the edge and hides most of it. Worth
doing during Phase 4 regardless.

---

## Phase 2 — Backups — done

Dozzle is live behind basic-auth, nightly `restic` backups are running (7 daily / 4 weekly /
3 monthly retention, restore tested byte-for-byte), and `ops/` now exists as the mechanism
for changing the box without rebuilding it — see README's Backups and Layout sections for
the details.

## Phase 3 — Prove the loop — done

FreshRSS was the guinea pig.

1. Done — `freshrss.tf` became `projects/freshrss/compose.yml`, live on `read.waqasali.dev`.
   Data is bind-mounted at `./data` (→ `/srv/freshrss/data`) rather than a named volume,
   so the nightly backup picks it up with no per-project config.
2. Done — `.github/workflows/deploy.yml`: build → push GHCR → SSH → ship compose file →
   `compose pull && up -d` → poll the host until it responds. Callable by any repo in
   ~10 lines (`build: false` skips the build/push steps for pre-built images, as FreshRSS's
   own caller workflow, `deploy-freshrss.yml`, does). A dedicated CI deploy key — distinct
   from the personal one `make sync` uses — was added to the `deploy` user via
   `ops/provision.sh`.
3. Done — `docs/new-project.md`: the checklist for a new app repo — compose file with the
   three labels plus the data-bind-mount convention, the ~10-line caller workflow, first
   deploy.

Verified live: pushing `projects/freshrss/compose.yml` to `main` triggered the workflow,
which shipped the compose file, brought the container up, and Traefik issued a real
Let's Encrypt cert for `read.waqasali.dev` with no manual step.

**Not yet exercised:** FreshRSS lives inside `hub` (it has no upstream repo of its own),
so the original "done when" — a project going from an *empty separate repo* to live HTTPS
by following `docs/new-project.md` alone — is still open. The mechanics are proven either
way; the first real app repo (or Phase 4's StudentBase) is what closes that gap.

## Phase 4 — Migrate StudentBase

The risky phase. Everything above must be solid, including a tested restore.

**Move it as-is. Improve it afterwards.** An earlier draft of this phase bundled the
Postgres 10 → 17 upgrade and a Next.js/Apollo service split into the cutover. Neither is
required to change hosts, and both inflate the one step where a mistake is user-visible.
The app runs today under a single container with a supervisor `start.sh`; it runs
identically in a container on the new box. Postgres needs no logical migration at all —
same version, same architecture, so a stopped-and-copied `PGDATA` is byte-for-byte
sufficient, with no dump/restore to rehearse and no row counts to verify. Coupling an
EOL-database upgrade to a DNS cutover means a bad upgrade and a bad cutover become the
same incident. Sequential is strictly safer, and everything deferred gets done later
against a box that already has working backups and a powered-off escape hatch.

Status as of 2026-08-09: **live** on hub. `studentbase.app` and `api.studentbase.app`
resolve to the hub box and serve real traffic against the migrated database (row counts
verified equal — 6390 — between the pre-cutover `pg_dumpall` and the live database before
the DNS flip). Full runbook, including the bugs found getting here, is
`docs/studentbase-cutover.md`.

1. **`prevent_destroy` on the server** — done, `terraform/server.tf`.
2. **`/srv/studentbase/compose.yml`** — done. One deviation from "unchanged": the
   Dockerfile's `HEALTHCHECK` used `localhost`, which resolves to `::1` first under bridge
   networking (unlike the droplet's `--network=host`) and Next.js only binds IPv4 — so the
   container sat permanently unhealthy and Traefik silently refused to route to it. Fixed
   to `127.0.0.1`. Postgres also needed no `user:` override, despite the copied PGDATA
   landing owned by `deploy` (uid 1000) rather than its usual uid 999 — the image's own
   entrypoint chowns it on boot, same as it always has.
3. **Secrets** — done: sops+age, CI recipient rotated (the original was unrecoverable —
   `make secrets-ci-init` prints it once and used to shred it; that target now writes it to
   a file instead). Credentials were copied from the droplet's `/env` as-is, not yet
   rotated — still open, see Phase 5.
4. **Routing** — done, including the GHCR-private-by-default and Traefik-silently-excludes-
   unhealthy-containers issues above.
5. **Copy the data** — done. `pg_dumpall` backup taken first; PGDATA stopped-and-copied,
   2113 files both sides; Redis started empty as planned.
6. **Cutover** — DNS flipped without the full 30-minute TTL wait; a few resolvers (including
   Let's Encrypt's) briefly still hit the stopped old droplet before converging. Traefik
   retried ACME automatically once DNS caught up — no manual fix needed. Old droplet is
   stopped (containers only) but still powered on, kept as the rollback target.
7. **Decommission** — done early and taken further than planned (ahead of the week-long
   hold, once the cutover itself was verified rather than waiting on the droplet as a
   time-based ritual). `deployment/terraform/` is gone from StudentBase's repo entirely —
   not just the droplet/web modules. Everything it managed now lives in hub's own
   Terraform: `prod_api`/`prod_frontend` in `terraform/dns-studentbase.tf` (done, imported,
   verified live); the CDN, both Spaces buckets, and every mail/SPF/DKIM/icloud DNS record
   in `terraform/studentbase-cdn.tf` (written, not yet applied — needs hub's DigitalOcean
   token, not available on the machine that did this reorg; the certificate chain is
   freshly recreated rather than imported, since ACME can't hand back a private key). Full
   detail and the exact import commands are in `docs/studentbase-cutover.md`. `deploy.yaml`
   and `backup_db.yml` (already broken — it read a now-deleted `terraform output`) are
   deleted; `deploy-hub.yml` is renamed to `deploy.yml`, push-triggered. Still open: run the
   `studentbase-cdn.tf` imports and apply, delete the old DO certificate object once the CDN
   is confirmed on the new one, power off the old droplet after the hold.

No schema change happened at cutover, so no migration ran — see Phase 5 for how the next
one will.

**Done when:** studentbase.app serves from the new box, the old droplet is off, and a
deploy is a `git push` rather than a 17-variable `terraform apply`. Two of three remain.

## Phase 5 — Deferred from the cutover, then cleanup

**Migrations — needed before the first deploy after cutover, not for the cutover itself.**
Today's mechanism is `deployment/terraform/modules/server/migration.tf`: scp `prisma/` to
the box, then `docker run node:lts` with `npm install -g prisma@^4.16.2 && prisma migrate
deploy`, triggered by a `filesha1` of the schema. It dies with the Terraform deploy path.

Either replacement needs the same packaging work first, because the runtime image cannot
run migrations as built: `server-prod-deps` installs `--omit=dev` and `prisma` is a *root*
devDependency, so only the generated client at `node_modules/.prisma` survives into
`runner` — the CLI does not, and neither does `server/prisma/migrations/`. The
`server-deps` stage has both already (it copies `server/prisma/` wholesale and runs the
CLI for `prisma generate`), which makes it the natural base.

Two options, **decision still open**:

- *One-shot before `up -d`* — a `migrate` target off `server-deps`, pushed as a second tag,
  run via `docker compose run --rm` between `pull` and `up -d`. Needs a `migrate-service`
  input on `.github/workflows/deploy.yml`; the existing `set -eu` aborts the deploy on a
  non-zero exit. A failed migration leaves the old container still serving — no downtime.
- *In the container's entrypoint, before starting the server* — simpler, no second image or
  workflow change, but it puts the CLI and schema-modifying privileges in the production
  image, and a failed migration crash-loops the new container after the old one is already
  gone. You're down until you roll back rather than aborting cleanly.

Either way, migrations must be backwards-compatible with the running code (expand/contract:
add nullable, backfill, drop in a later deploy) — old containers serve against the new
schema briefly. And if the service split below happens, gate migrations to one service:
both come from the same image and would otherwise both run on boot.

**Also deferred out of Phase 4:**

- **Postgres 10.3 → 17.** Dump from the running 10.3 container, restore into 17, verify row
  counts and a real login flow. Do it against a scratch directory first. Now a standalone
  operation on a box with tested backups and the old droplet still available.
- **Split the container into two services** from the same image with different commands. A
  crashing API stops taking the frontend down with it, and each gets its own healthcheck
  and restart policy. The existing `HEALTHCHECK` splits cleanly into the two endpoints it
  already probes.

**Cleanup:**

- Drop the monthly `schedule:` cron on StudentBase's deploy workflow. Deploys become
  push-triggered, and cert renewal no longer depends on Terraform running at all.
- Cloudflare in front of `studentbase.app` for edge caching (see the latency note in §3).
- Consider Spaces → Cloudflare R2 (free egress) once only Terraform state and backups
  remain there.
- Renovate or Dependabot on image tags in the compose files.

---

## Open question

**One box, real users, and experiments together.** Consolidating is the cost win and the
whole point, but it does put StudentBase on the same host as things you're actively
breaking. No HA is fine and you've called that; the mitigations that matter are memory
limits on every experimental service so one runaway container can't OOM Postgres, and the
Phase 2 backups being genuinely tested. Both are in the plan — flagging it so it stays a
choice rather than a surprise.
