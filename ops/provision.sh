#!/bin/sh
# Host-level changes to an *existing* box over SSH, as root — the alternative to
# editing cloud-init.yml, which requires destroying and recreating the server.
# Idempotent, safe to re-run. Run via `make provision`, which rsyncs ops/systemd/ first.
set -eu

apt-get update
apt-get install -y restic

# json-file's default driver grows unbounded and will fill the disk over time.
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
EOF
systemctl reload-or-restart docker

# Reclaims old images on a timer (docker-prune.{service,timer} in ops/systemd/),
# since nothing else does and a box nobody logs into will eventually fill its disk.
#
# Targeted prunes, not `docker system prune` — that would also remove volumes
# (deleting traefik's acme.json while a stack is down) and networks (`edge` is
# `external` everywhere, so losing it would strand every stack).
#
# A script, not inline ExecStart= lines, so `make prune` runs exactly what the
# timer runs without the deploy user needing sudo.
cat > /usr/local/bin/docker-prune <<'EOF'
#!/bin/sh
set -eu
docker container prune -f
docker image prune -af
docker builder prune -af --filter until=168h
docker system df
EOF
chmod 0755 /usr/local/bin/docker-prune

# journald defaults to 10% of disk (8 GB here) — cap it well below that.
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-hub.conf <<'EOF'
[Journal]
SystemMaxUse=500M
MaxRetentionSec=1month
EOF
systemctl restart systemd-journald

# Security upgrades stay automatic; reboots stay manual — no HA, so an unattended
# 4am reboot is downtime nobody chose.
cat > /etc/apt/apt.conf.d/51unattended-upgrades-hub <<'EOF'
Unattended-Upgrade::Automatic-Reboot "false";
EOF

# fail2ban's sshd jail is disabled by default — without this it runs but bans no one.
cat > /etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl restart fail2ban

# Internal-only network for the Docker API proxy (stacks/traefik/compose.yml).
# --internal: no route out, and nothing on `edge` can reach it — only containers
# explicitly attached (Traefik, Dozzle) see the filtered API.
docker network inspect socket-proxy >/dev/null 2>&1 || docker network create --internal socket-proxy

# Quarantine network for the assistant (../assistant), an LLM driving a shell and a
# browser. On `edge` it would be one DNS lookup from Traefik's API, Dozzle, ynab-mcp
# and StudentBase's Postgres, none of which authenticate a caller already inside the
# perimeter; here it gets Traefik and nothing else. Not --internal, unlike
# socket-proxy — the agent still needs the open web, it just loses the neighbours.
docker network inspect assistant >/dev/null 2>&1 || docker network create assistant

systemctl daemon-reload
systemctl enable --now backup.timer docker-prune.timer

# CI's deploy key, separate from your personal one so a leaked Actions secret
# doesn't hand out interactive access. Appended (cloud-init's key must stay too);
# skips if already present.
DEPLOY_HOME=/home/deploy
CI_DEPLOY_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPPG6/GuZzFrXSkqIaZif+vM+abFn9/no3GksEUh+yzc hub-ci-deploy'
grep -qxF "$CI_DEPLOY_KEY" "$DEPLOY_HOME/.ssh/authorized_keys" 2>/dev/null || \
  echo "$CI_DEPLOY_KEY" >> "$DEPLOY_HOME/.ssh/authorized_keys"
chown deploy:deploy "$DEPLOY_HOME/.ssh/authorized_keys"
chmod 0600 "$DEPLOY_HOME/.ssh/authorized_keys"
