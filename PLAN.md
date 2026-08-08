# Hub: plan to become the home for all side projects

Goal: one cheap box hosting several side projects, where adding a project means writing a
compose file and a DNS-free subdomain label — not editing another project's
infrastructure code. Plus enough monitoring to know when something breaks without SSHing in.

Status as of 2026-08-08: `hub` is **live** on Hetzner (fsn1), wildcard DNS resolves,
Traefik is issuing real Let's Encrypt certs, and Dozzle is up behind basic-auth. `waqasali.dev`
apex stays on GitHub Pages. StudentBase is still on its own DO droplet at `188.166.206.48`,
untouched. Phase 3 is proven: the reusable GitHub Actions deploy workflow shipped FreshRSS
to `/srv/freshrss` over CI, Traefik issued a real cert for `read.waqasali.dev` with no
manual step, and its data lands at `/srv/freshrss/data` where the nightly backup picks it
up automatically.

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
| Postgres 17 | ~0.4 GB |
| Redis (already capped `maxmemory 150mb`) | ~0.2 GB |
| Dozzle | ~0.05 GB |
| FreshRSS | ~0.3 GB |
| **Subtotal** | **~2.2 GB** |

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

**Before anything else, pin the box down.** Up to now a destructive `terraform apply` has
cost nothing, and editing `cloud-init.yml` deliberately rebuilds the server — that's the
Phase 1 iteration loop. The moment real data lands here that flips into the worst failure
mode in this plan. Add to `hcloud_server.hub`:

```hcl
lifecycle {
  ignore_changes  = [ssh_keys]
  prevent_destroy = true
}
```

Not `ignore_changes = [user_data]`: that silences the diff without applying it, so
`cloud-init.yml` drifts into fiction and you discover it during the rebuild you were
already having a bad day about. `prevent_destroy` errors on *any* replacement — image
bump, `server_type` change, `user_data` edit — and errors loudly. From here on,
cloud-init changes are applied by hand on the box and backfilled into the file.

1. **Postgres 10 → 17.** The genuinely delicate step, and the one to rehearse first: dump
   from the old box, restore into the new Postgres 17 container, verify row counts and a
   real login flow. Do a full dry run into a scratch directory before the real cutover.
2. **Split the container into two services** from the same image with different commands.
   Today one `start.sh` runs Next.js and Apollo under a hand-rolled supervisor loop that
   kills the container when either dies. As two compose services, a crashing API stops
   taking the frontend down with it, and each gets its own healthcheck and restart policy.
   The existing `HEALTHCHECK` splits cleanly into the two endpoints it already probes.
3. **Migrations** as a one-shot `docker compose run --rm migrate` using the app image,
   replacing the `remote-exec` that `docker run`s `node:lts` and `npm install -g prisma`
   on every apply.
4. **Secrets**: `/srv/studentbase/.env`, 0600, written by CI from repo secrets — or, if
   StudentBase's stack ends up living here rather than in its own repo, the same
   sops+age pattern the platform stacks use (see README's Secrets section). Rotate
   everything from the old `terraform.tfvars` during this step — treat all of it as
   compromised-by-exposure.
5. **Routing**: labels for `studentbase.app`, `www.studentbase.app`, and
   `api.studentbase.app`. The `files/api.studentbase.app` nginx file and all the ACME
   plumbing in `deployment/terraform/` are then dead.
6. **Cutover**: drop DNS TTL a day ahead, run alongside the old box, verify against the new
   IP directly via `/etc/hosts`, flip the A records, keep the old droplet powered off — not
   destroyed — for a week.
7. **Decommission**: delete `modules/web`, `modules/server`, and every SSH provisioner from
   StudentBase's repo. Its deploy workflow becomes the Phase 3 pattern. Keep Spaces, the
   CDN, and the DNS records.

**Done when:** studentbase.app serves from the new box, the old droplet is off, and a
deploy is a `git push` rather than a 17-variable `terraform apply`.

## Phase 5 — Cleanup

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
