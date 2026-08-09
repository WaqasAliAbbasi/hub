# Adding a new project

A project is a directory on the box (`/srv/<project>/`) plus a repo that owns its own
`compose.yml` and deploy workflow. Nothing in `hub` changes.

## 1. Compose file

In your app's own repo, at `compose.yml`:

```yaml
name: <project>

services:
  web:
    image: ghcr.io/<org>/<repo>:${IMAGE_TAG}
    restart: always
    volumes:
      - ./data:/path/to/app/data
    labels:
      - traefik.enable=true
      - traefik.http.routers.<project>.rule=Host(`<project>.waqasali.dev`)
      - traefik.http.routers.<project>.tls.certresolver=le
      - traefik.http.services.<project>.loadbalancer.server.port=<container-port>
    networks:
      - edge
    mem_limit: 512m
    security_opt:
      - no-new-privileges:true

networks:
  edge:
    external: true
```

`image` must use the literal `${IMAGE_TAG}` placeholder — the deploy workflow substitutes
it with the git SHA it just built, so a rollback is just re-running an old workflow run.
Set `mem_limit` so a runaway container can't OOM everything else on the box.

If the app has state worth keeping, bind-mount it at `./data` rather than a named
volume — the nightly backup only walks `/srv/*/data`, and a named volume is invisible to
it. `*.waqasali.dev` is a wildcard DNS record already pointed at the box, so a new
subdomain needs no DNS change — Traefik requests the cert itself.

## 2. Deploy workflow

In your app's own repo, at `.github/workflows/deploy.yml`:

```yaml
name: deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: waqasaliabbasi/hub/.github/workflows/deploy.yml@main
    with:
      project: <project>
      host: <project>.waqasali.dev
    secrets:
      SSH_HOST: ${{ secrets.HUB_SSH_HOST }}
      SSH_KEY: ${{ secrets.HUB_SSH_KEY }}
    permissions:
      contents: read
      packages: write
```

`HUB_SSH_HOST` is the box's IP (`make ip` in `hub`). `HUB_SSH_KEY` is the CI deploy
private key — never committed anywhere. Both are repo secrets on the app repo, not `hub`.

## 3. Secrets (only if the app needs them)

Commit them encrypted, next to the compose file that consumes them:

```sh
make secrets FILE=projects/<project>/secrets.enc.env   # opens $EDITOR, encrypts on save
```

Point the workflow at it with `secrets-path:` and pass `SOPS_AGE_KEY`, as
`deploy-ynab-mcp.yml` does. On every deploy the workflow decrypts it to
`/srv/<project>/.env` at 0600, before `docker compose up`, so `env_file: .env` just works.

This needs `make secrets-ci-init`, once ever, which mints a second age key scoped to
`projects/**` that only CI holds. Terraform and platform-stack secrets stay laptop-only.

If the app writes to `./data` as a non-root user, add `user: "1000:1000"` to the service —
the workflow creates `/srv/<project>/data` as `deploy` (uid 1000), and an image with its
own baked-in user typically can't write to it otherwise. Symptom: a permission error on
startup, looping via `restart: always`. `chown` isn't the fix; `deploy` has no sudo.

## 4. First deploy

Push to `main`. The workflow builds the image, pushes it to GHCR, copies `compose.yml` to
`/srv/<project>/` on the box, and runs `docker compose up -d` there, then polls
`https://<project>.waqasali.dev` until it responds.

## Done when

The app is live at `https://<project>.waqasali.dev` with a valid certificate, and every
subsequent deploy is a `git push` — no SSH, no Terraform, no edit to `hub`.
