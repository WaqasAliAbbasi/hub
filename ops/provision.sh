#!/bin/sh
# Applies host-level changes to an *existing* box over SSH, as root — the
# alternative to editing cloud-init.yml, which can only take effect by
# destroying and recreating the server. Safe to re-run: every step here is
# idempotent (an already-installed package, an unchanged file, or an
# already-enabled unit is a no-op).
#
# Run via `make provision`, which rsyncs ops/systemd/ into place first.
set -eu

apt-get update
apt-get install -y restic

# Docker's default json-file driver grows without bound and will eventually fill
# the disk on a box nobody logs into.
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
EOF
systemctl reload-or-restart docker

# Every deploy leaves the previous image behind, and nothing reclaims it. On a
# box nobody logs into that is a slow disk-full outage, so reclaim on a timer
# (docker-prune.{service,timer} in ops/systemd/).
#
# Three targeted prunes rather than `docker system prune`, which would also take
# volumes and networks:
#   - volumes: it removes any named volume with no container attached, which
#     would delete traefik's acme.json the moment a stack is down.
#   - networks: it removes any network with no container attached, and `edge` is
#     declared `external` by every stack — losing it turns a brief outage into a
#     box where nothing can come back up.
#
# `until=168h` on images filters by the image's *build* date, not when it was
# pulled, so it would not preserve a week of your own deploys anyway. Anything
# with no container referencing it goes; a rollback is a re-pull.
# A script rather than three ExecStart= lines so `make prune` can run exactly
# what the timer runs, without the deploy user needing sudo.
cat > /usr/local/bin/docker-prune <<'EOF'
#!/bin/sh
set -eu
docker container prune -f
docker image prune -af
docker builder prune -af --filter until=168h
docker system df
EOF
chmod 0755 /usr/local/bin/docker-prune

# journald defaults to 10% of the filesystem, which on an 80 GB disk is 8 GB of
# logs nobody reads. Cap it well below that; fail2ban's systemd backend and
# `journalctl -u docker-prune` only need recent history.
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-hub.conf <<'EOF'
[Journal]
SystemMaxUse=500M
MaxRetentionSec=1month
EOF
systemctl restart systemd-journald

# Unattended security upgrades. Reboots are left manual — this is a single box
# with no HA, so an unattended 4am reboot is downtime nobody chose.
cat > /etc/apt/apt.conf.d/51unattended-upgrades-hub <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
EOF

# fail2ban ships with the sshd jail disabled by default (jail.conf is the
# package default and isn't meant to be edited) — without this, the service
# runs but bans no one. journald backend needs no logpath.
cat > /etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl restart fail2ban

systemctl daemon-reload
systemctl enable --now backup.timer docker-prune.timer

# CI's deploy key, separate from your personal one (~/.ssh/id_rsa.pub, installed by
# cloud-init at first boot) — so a leaked Actions secret doesn't hand out the same
# key you use interactively. Appended, not written, since cloud-init's key must
# stay too. Idempotent: skips if already present.
DEPLOY_HOME=/home/deploy
CI_DEPLOY_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPPG6/GuZzFrXSkqIaZif+vM+abFn9/no3GksEUh+yzc hub-ci-deploy'
grep -qxF "$CI_DEPLOY_KEY" "$DEPLOY_HOME/.ssh/authorized_keys" 2>/dev/null || \
  echo "$CI_DEPLOY_KEY" >> "$DEPLOY_HOME/.ssh/authorized_keys"
chown deploy:deploy "$DEPLOY_HOME/.ssh/authorized_keys"
chmod 0600 "$DEPLOY_HOME/.ssh/authorized_keys"
