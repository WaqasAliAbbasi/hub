# Hub

One small server hosting all my side projects. Adding a project means writing a compose
file with three labels — no DNS change, no certificate step, and nothing to edit here.

See [PLAN.md](PLAN.md) for the full roadmap and the reasoning behind each choice.

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

That last row is the point. Application workloads are deliberately **not** managed here,
so shipping an app never means running Terraform.

`terraform/` vs `ops/` is a real distinction, not a style choice: cloud-init only runs once,
at first boot — there is no "re-run cloud-init" on an existing Hetzner server. Editing
`cloud-init.yml` therefore forces Terraform to destroy and recreate the box to take effect.
`ops/` is how you add a package, a config file, or a systemd unit *without* that: `make provision` pushes
`ops/systemd/` and runs `ops/provision.sh` over SSH as root, idempotently, against the box
that's already running. `stacks/`' `make up` is the same idea one layer up, for containers.

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

Every `make` target that touches Terraform supplies the credentials itself from that one
encrypted file — there is nothing to `export` and no `terraform.tfvars`.

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
are all correct.

If the certificate does not appear, `make logs` and look for ACME errors — the usual
cause is DNS not yet propagated, since Let's Encrypt must reach the box over port 80.

## Secrets

Every credential this repo needs is committed here, sops-encrypted to a single `age` key
that only you hold. There is one command to edit any of them, and one thing to back up.

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

`make secrets` opens `$EDITOR` on the decrypted content and re-encrypts on save, creating
the file if it doesn't exist. No flags, no SSH, no `--age`: `.sops.yaml` (committed —
it's public-key material) names the recipient, and sops finds your private key at
`~/.config/sops/age/keys.txt` on its own.

**Back up `~/.config/sops/age/keys.txt` to your password manager.** It is the only thing
that can decrypt this repo, and nothing else has a copy.

Encrypted-and-committed rather than plaintext-and-gitignored because a gitignore rule only
stops a file being picked up automatically — it does nothing once something's been `git
add`ed, which is exactly how a real credential nearly ended up in this repo's history.
Encrypted, the committed file is inert.

### How it reaches the box

`make sync` decrypts on **your laptop**, into a throwaway staging directory, and rsyncs the
plaintext across at 0600. The box holds no age key, no `sops` binary, and no way to decrypt
anything in this repo.

That's the design decision worth understanding, because the obvious alternative — keep the
key on the box and let it decrypt at runtime — is what this replaced, and it was worse on
every axis. It bought "no plaintext at rest on the box", which was never real: the box
already held the key that decrypts everything, so anyone with root had both. In exchange it
cost a key that existed in exactly one place and died with the disk, orphaning every
encrypted file on rebuild; a `sops` binary pinned by checksum in `cloud-init.yml`, patchable
only by rebuilding the server; and an edit command that SSHed in to `cat` the key and parse
its public half out of a comment. Decrypting locally deletes all of that.

The consequence to be aware of: **a rebuild is now cheap** (a fresh box needs nothing but
`make up`), and **root on the box reads the secrets that box uses** — but only those, not
the Terraform tokens, which never leave your laptop.

### Admin auth

Dozzle (and any future admin surface) sits behind Traefik's `admin-auth` middleware
(`stacks/traefik/dynamic/middlewares.yml`), backed by an htpasswd file. Generate a line with
`docker run --rm httpd:alpine htpasswd -nbB <user> <password>` and put it in
`stacks/traefik/admin-users.enc`. `make sync` writes it to
`/srv/platform/traefik/admin-users`; Traefik's file provider reloads it live, no restart.

If a secret fails to decrypt, `make sync` aborts before rsync runs — so a bad or missing
secret can't reach the box as an empty file, and `--delete` can't strip an existing one.

## Backups

`restic` runs nightly (`backup.timer`, 03:00 UTC, installed via `make provision` — see
`ops/systemd/backup.{service,timer}`) against every `/srv/*/data`, plus a `pg_dumpall` of
any running Postgres container first (a logical dump, not a copy of the live data
directory). Retention is 7 daily / 4 weekly / 3 monthly, auto-pruned.

Credentials come from `stacks/backup/secrets.enc.env` (see Secrets above), which `make sync`
decrypts to `/srv/platform/backup/.env` at 0600. The scoped `hub-backup` Spaces key is
deliberately separate from the one authenticating Terraform's state backend — get its values
with `terraform output -raw backup_access_key_id` / `backup_secret_access_key` after
`terraform apply` creates `terraform/backup.tf`'s resources.

**`RESTIC_PASSWORD` has no recovery path** — it's the encryption key for every backup;
losing it makes the backups in Spaces unrecoverable. Save it somewhere durable, separate
from the backups it protects and separate from this repo.

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
`/srv/my-project/` and keep anything stateful under `/srv/my-project/data/` so the
backup job (Phase 2) picks it up automatically.

`mem_limit` is not optional on experimental services: this is a single box with no HA,
and one runaway container must not be able to OOM a neighbour.

## Known tradeoffs

- **Traefik mounts the Docker socket read-only.** That is still root-equivalent access to
  the host for anything that compromises Traefik. The fix is a socket proxy exposing only
  the container-list endpoints; worth adding if this box ever hosts something sensitive.
- **Single box, no HA.** Reboots are downtime. Deliberate.
- **`user_data` changes replace the server.** This is why `cloud-init.yml` is frozen after
  day one and `ops/`/`make provision` exists for everything after — see "Layout" above.

## Migrating from the K3s attempt

This repo previously provisioned single-node K3s on DigitalOcean. K3s' ~1 GB control-plane
overhead was too much of an 8 GB box that also has to host StudentBase, so it was replaced
with plain Docker + Traefik, which does the same routing job for ~200 MB.

Terraform state moved to a new key (`hub.tfstate`), so the old state at
`terraform-server.tfstate` is untouched. **Check the DigitalOcean console for leftover
resources from that attempt** — a `hub-k3s-cluster` droplet, the `hub-k3s-key` SSH key, and
a `hub` A record — and remove them by hand.
