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

## 4. Pre-deploy step (schema migrations, mostly)

`pre-deploy-service` names a compose service the workflow runs **to completion** between
`docker compose pull` and `up -d`. A non-zero exit aborts the deploy with production
untouched. Schema migrations are the case this exists for; anything that must succeed
before new code starts fits.

Add the service, behind a profile so `up -d` never starts it:

```yaml
  migrate:
    image: ghcr.io/<org>/<repo>:${IMAGE_TAG}
    command: ["./bin/migrate"]
    profiles: [migrate]
    env_file: .env
    depends_on:
      postgres:
        condition: service_healthy
    restart: "no"
```

```yaml
      pre-deploy-service: migrate
```

The profile is required, not stylistic — the workflow fails the deploy if the service is
missing from `docker compose config --services`, because a non-profiled one would be
started a second time by `up -d`, concurrently with the app it just ran for.

Because it runs while the **previous** release is still serving, a migration must be
backwards-compatible with the code already deployed: expand/contract (add nullable,
backfill, drop in a later deploy), never a rename in one step.

### When the tooling can't ship in the runtime image

Often it shouldn't: a migration CLI is usually a devDependency stripped from the runtime
image, and the container serving traffic has no business holding rights to rewrite the
schema. `pre-deploy-target` names a Dockerfile stage that does have them:

```yaml
      pre-deploy-service: migrate   # compose service to run
      pre-deploy-target: migrate    # Dockerfile stage to build it from
```

That stage is built and pushed as `:sha-<sha>-<target>` alongside the app image and
substituted into compose as `${PRE_DEPLOY_IMAGE_TAG}` — use that in place of
`${IMAGE_TAG}` on the service above. It needs `build: true`; the workflow fails fast if
not. Omit `pre-deploy-target` and `${PRE_DEPLOY_IMAGE_TAG}` resolves to the app image, so
either shape substitutes cleanly.

`StudentBase` does this with `prisma migrate deploy`.

## 5. First deploy

Push to `main`. The workflow builds the image, pushes it to GHCR, copies `compose.yml` to
`/srv/<project>/` on the box, and runs `docker compose up -d` there, then polls
`https://<project>.waqasali.dev` until it responds.

## Done when

The app is live at `https://<project>.waqasali.dev` with a valid certificate, and every
subsequent deploy is a `git push` — no SSH, no Terraform, no edit to `hub`.
