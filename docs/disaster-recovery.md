# Disaster recovery

Everything here is rebuildable from the repo *except two private keys*, and both live
only on your laptop. Nothing else needs backing up: the repo is on GitHub, Terraform
state is in Spaces, and `/srv/*/data` goes to restic nightly.

## What to keep in your password manager

**`~/.config/sops/age/keys.txt`** — the one that matters. It decrypts every `*.enc*` file
in this repo:

| File | Contents |
|---|---|
| `terraform/secrets.enc.env` | Hetzner + DigitalOcean tokens, Spaces keys (also the state backend's credentials) |
| `stacks/backup/secrets.enc.env` | `RESTIC_PASSWORD`, which encrypts every backup |
| `stacks/traefik/admin-users.enc` | admin basic-auth users |
| `projects/*/secrets.enc.env` | each project's own secrets |

Losing it is unrecoverable — backups don't help, since the restic password that would
open them is itself encrypted with this key, and this key was never in a snapshot.

**`~/.ssh/id_rsa`** (with `.pub`) — provisioned to `deploy` by cloud-init and registered
as the Hetzner SSH key, so it's also root's key and what `make provision` uses. Losing it
locks you out of the *running* box; recoverable via the Hetzner console, or a rebuild.

Nothing else. `HUB_SSH_KEY` and `SOPS_AGE_KEY` exist only as GitHub secrets, re-mintable
as long as you still hold the age key. CI's public key is committed in
`ops/provision.sh`, so a rebuilt box gets CI access back automatically.

## Verify the backup restores

A pasted key that was never tested is not a backup. Against the restored file, not the
one already in place:

```sh
SOPS_AGE_KEY_FILE=/path/to/restored/keys.txt sops -d terraform/secrets.enc.env
```

## Lost the laptop, box still running

```sh
git clone https://github.com/WaqasAliAbbasi/hub.git && cd hub
install -D -m 600 <restored-age-key> ~/.config/sops/age/keys.txt
install -D -m 600 <restored-ssh-key>  ~/.ssh/id_rsa
make ip && make ssh          # confirms both keys work
```

Install `terraform`, `sops`, `age`, `rsync`. Nothing on the box changed, so there's
nothing to redeploy.

## Lost the box

```sh
make apply                   # new server, firewall, and wildcard DNS
make provision               # packages, systemd timers, CI's deploy key
make up                      # traefik, dozzle, backup
```

**Then update the `HUB_SSH_HOST` repo secret to the new IP** (`make ip`) — Terraform
can't reach it, and every project's deploy workflow SSHes there. Deploys fail until you do.

Restore data *before* bringing projects back, or they'll initialise empty and overwrite
good snapshots on the next backup run. As root on the box:

```sh
cd /srv/platform/backup && set -a && . ./.env && set +a
restic snapshots                          # find the one you want
restic restore latest --target / --dry-run -vv   # check first
restic restore latest --target /          # paths are absolute: /srv/<project>/data
```

Restored as root, so `/srv/<project>/data` keeps its original `deploy` (uid 1000)
ownership, which is what the containers need.

Then re-run each project's deploy workflow from the Actions tab — it ships
`compose.yml`, decrypts secrets to `/srv/<project>/.env`, and starts it.

## Lost both

Same as above, *provided the age key survived somewhere*. If it didn't, the Hetzner and
DigitalOcean accounts need their own password resets, and every backup in Spaces is
unreadable forever — the whole reason the age key is tier one.
