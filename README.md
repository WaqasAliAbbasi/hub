# Hub

One small server hosting all my side projects. Adding a project means writing a compose
file with three labels — no DNS change, no certificate step, and nothing to edit here.

## How it works

```
Hetzner CX32 (2 vCPU / 8 GB, fsn1)
│
├── /srv/platform/         synced from stacks/ in this repo
│   └── traefik/           :80 :443 — routes by Docker label, auto Let's Encrypt
│
└── /srv/<project>/        owned by each project's own repo
```

`*.waqasali.dev` is a single wildcard DNS record pointing at the box, so any new
subdomain works the moment a container claims it. Traefik watches the Docker socket,
picks up containers labelled `traefik.enable=true`, and obtains a certificate per host
over HTTP-01.

The apex `waqasali.dev` is untouched and stays on GitHub Pages.

## Layout

| Path | Owns | Changes |
|---|---|---|
| `terraform/` | Server, firewall, wildcard DNS, `cloud-init.yml` (day-one bootstrap only) | Rarely |
| `ops/` | Host-level changes to the *existing* box — packages, config files, systemd units | Occasionally |
| `stacks/` | Platform services (Traefik, Dozzle, ...) | Occasionally |
| Each app's own repo | That app's `compose.yml` and deploy workflow | Constantly |

Application workloads are deliberately **not** managed here, so shipping an app never
means running Terraform. Deploy mechanism per app repo: build → push to **GHCR** → SSH →
`docker compose pull && docker compose up -d`, using a dedicated `deploy` user (not your
personal key) in the `docker` group.

Deliberately not Dokploy/Coolify: they'd wrap this stack in a UI, but add a stateful
control plane with its own upgrade path and failure modes. ~40 lines of compose you
fully understand is the better trade at this size.

`cloud-init` only runs at first boot — there is no "re-run cloud-init" on an existing
Hetzner server, so editing `cloud-init.yml` forces Terraform to destroy and recreate the
box. `ops/` is how you add a package, config file, or systemd unit without that: `make
provision` pushes `ops/systemd/` and runs `ops/provision.sh` over SSH as root,
idempotently. `stacks/`'s `make up` is the same idea one layer up, for containers.

## Setup

Prerequisites: `terraform`, `rsync`, `sops`, `age` (`sudo pacman -S sops age`), an SSH key
at `~/.ssh/id_rsa.pub`, a Hetzner Cloud API token, and a DigitalOcean token with DNS access.

```sh
make secrets-init                                # once: your age key + .sops.yaml
make secrets FILE=terraform/secrets.enc.env      # tokens + Spaces keys, see the .example

make init
make plan
make apply     # ~60s for the server, plus ~2min of cloud-init
```

Every `make` target that touches Terraform supplies credentials from that one encrypted
file — nothing to `export`, no `terraform.tfvars`.

Then bring up the platform stacks:

```sh
make secrets FILE=stacks/backup/secrets.enc.env  # see the .example alongside it
make secrets FILE=stacks/traefik/admin-users.enc # docker run --rm httpd:alpine htpasswd -nbB <user> <pass>

make up        # sync stacks/ to /srv/platform and `docker compose up -d` each one
make provision # rsync ops/ and apply it over root SSH (packages, config files, systemd units)
```

## Verifying

After `make up`, hit an admin surface (see below) or any project's own `Host()`:

```sh
curl -sI https://logs.waqasali.dev | head -1     # expect HTTP/1.1 401 (needs auth)
```

A valid certificate with no manual step means DNS, Traefik, ACME and the `edge` network
are all correct. If it doesn't appear, `make logs` and check for ACME errors — usually DNS
hasn't propagated yet.

## Secrets

Every credential this repo needs is committed here, sops-encrypted to a single `age` key
that only you hold.

| File | Holds | Used by |
|---|---|---|
| `terraform/secrets.enc.env` | Hetzner + DigitalOcean tokens, account-level Spaces keys | Every `make` target that runs Terraform |
| `stacks/backup/secrets.enc.env` | Scoped `hub-backup` Spaces key, restic repo + password | `backup.timer` on the box |
| `stacks/traefik/admin-users.enc` | bcrypt htpasswd for the admin UIs | Traefik's `admin-auth` middleware |

Each has a committed `.example` next to it listing the keys it expects.

```sh
make secrets-init                                # once, ever
make secrets FILE=stacks/backup/secrets.enc.env  # add, edit, or rotate
```

`make secrets` opens `$EDITOR` on the decrypted content and re-encrypts on save.
`.sops.yaml` (committed — it's public-key material) names the recipient; sops finds your
private key at `~/.config/sops/age/keys.txt` on its own.

**Back up `~/.config/sops/age/keys.txt` to your password manager.** It is the only thing
that can decrypt this repo, and nothing else has a copy.

Encrypted-and-committed rather than plaintext-and-gitignored, since a gitignore rule does
nothing once a file's already been `git add`ed — which is how a real credential nearly
ended up in this repo's history.

### How it reaches the box

`make sync` decrypts on **your laptop**, into a throwaway staging directory, and rsyncs
the plaintext across at 0600. The box holds no age key, no `sops` binary, and no way to
decrypt anything in this repo.

This replaced keeping the key on the box and decrypting at runtime, which was worse: root
on the box already had both the key and everything it decrypts, while a key that exists
in exactly one place dies with the disk, orphaning every encrypted file on rebuild.
Decrypting locally means **a rebuild is now cheap**, and **root on the box only reads the
secrets that box uses** — never the Terraform tokens, which stay laptop-only.

### Admin auth

Dozzle (and any future admin surface) sits behind Traefik's `admin-auth` middleware
(`stacks/traefik/dynamic/middlewares.yml`), backed by an htpasswd file. Generate a line
with `docker run --rm httpd:alpine htpasswd -nbB <user> <password>` and put it in
`stacks/traefik/admin-users.enc`. `make sync` writes it to
`/srv/platform/traefik/admin-users`; Traefik's file provider reloads it live.

If a secret fails to decrypt, `make sync` aborts before rsync runs.

## Backups

`restic` runs nightly (`backup.timer`, 03:00 UTC, installed via `make provision`) against
every `/srv/*/data`, plus a `pg_dumpall` of any running Postgres container first.
Retention is 7 daily / 4 weekly / 3 monthly, auto-pruned.

Credentials come from `stacks/backup/secrets.enc.env`, decrypted by `make sync` to
`/srv/platform/backup/.env`. The scoped `hub-backup` Spaces key is separate from the one
authenticating Terraform's state backend — get its values with `terraform output -raw
backup_access_key_id` / `backup_secret_access_key`.

**`RESTIC_PASSWORD` has no recovery path.** Losing it makes every backup in Spaces
unrecoverable. Save it somewhere durable, separate from this repo.

To restore, on the box:

```sh
cd /srv/platform/backup && set -a && . ./.env && set +a && export HOME=/root
restic snapshots                          # find the snapshot you want
restic restore latest --target /somewhere # or a specific snapshot ID instead of `latest`
```

## Everyday commands

```sh
make up        # sync stacks and bring them up
make provision # apply ops/ (packages, config files, systemd units) to the existing box
make ps        # what is running
make logs      # tail traefik
make ssh       # shell on the box
make ip        # public IPv4
```

## Adding a project

Attach to the external `edge` network and declare a host rule:

```yaml
services:
  web:
    image: ghcr.io/waqasaliabbasi/my-project:sha-abc1234
    restart: always
    labels:
      - traefik.enable=true
      - traefik.http.routers.myproject.rule=Host(`my-project.waqasali.dev`)
      - traefik.http.routers.myproject.tls.certresolver=le
    networks: [edge, default]
    mem_limit: 512m

networks:
  edge:
    external: true
```

Router names (`myproject` above) must be unique across the whole box. Put the stack in
`/srv/my-project/` and keep anything stateful under `/srv/my-project/data/` so the backup
job picks it up automatically. Set `mem_limit` on every service — a single box with no HA
can't let one runaway container OOM a neighbour.

## Sizing

| Workload | Reserved |
|---|---|
| Docker daemon + Traefik | ~0.2 GB |
| StudentBase web + api | ~1.0 GB |
| Postgres | ~0.4 GB |
| Redis (capped `maxmemory 150mb`) | ~0.2 GB |
| Dozzle | ~0.05 GB |
| FreshRSS | ~0.3 GB |
| ynab-mcp | ~0.15 GB |
| **Subtotal** | **~2.3 GB** |

Running on a Hetzner **CX33** (4 vCPU / 8 GB, fsn1, ~€8/mo) for headroom — builds,
Postgres restores, and traffic spikes all want it. A **CX22** (2 vCPU / 4 GB, ~€4.35/mo)
fits today's workload with ~1.5 GB spare if the floor price matters more. Verify current
Hetzner pricing at order time.

## Known tradeoffs

- **Only the socket proxy holds the Docker socket.** Traefik and Dozzle talk to a
  GET-only filtered API (`socket-proxy` in `stacks/traefik/compose.yml`, on an
  `--internal` network created by `make provision`), so compromising either yields
  container metadata and logs, not root on the host.
- **Backups are versioned, not immutable.** The box's readwrite Spaces key could
  `restic forget` everything; bucket versioning keeps deleted objects recoverable
  for 30 days. The same key can still purge versions via the raw S3 API — Spaces
  has no object lock, so true immutability would need a second repo elsewhere.
- **Single box, no HA.** Reboots are downtime. Deliberate.
- **`user_data` changes replace the server.** Why `cloud-init.yml` is frozen after day one
  and `ops/`/`make provision` exists for everything after.
- **Real users share the box with experiments.** StudentBase's traffic runs alongside
  side-project containers you're actively breaking. Mitigated by `mem_limit` on every
  service plus restore-tested backups — not HA, but enough to make failure recoverable.

## Migrating from the K3s attempt

This repo previously provisioned single-node K3s on DigitalOcean. K3s' ~1 GB
control-plane overhead was too much for an 8 GB box that also hosts StudentBase, so it
was replaced with plain Docker + Traefik, which does the same routing job for ~200 MB.

Terraform state moved to a new key (`hub.tfstate`); the old state at
`terraform-server.tfstate` is untouched. **Check the DigitalOcean console for leftover
resources from that attempt** — a `hub-k3s-cluster` droplet, the `hub-k3s-key` SSH key,
and a `hub` A record — and remove them by hand.
