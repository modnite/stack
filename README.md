# The stack

One Docker Compose stack that runs the whole business:

| Service | What it is | Reached at |
| --- | --- | --- |
| `thrice-app`, `thrice-worker`, `thrice-migrate` | THRICE, the rental admin | `ADMIN_DOMAIN` |
| `site-app`, `site-migrate` | The studio website and its CMS | `SITE_DOMAIN` |
| `postgres` | One server, a separate database and login for each app | private |
| `redis` | THRICE's job queue and rate limits | private |
| `caddy` | HTTPS front door for both names | ports 80 and 443 |
| `backup`, `offsite` | Nightly dumps of both databases and the website's uploads, optionally copied off the machine | private |

The apps are built once, elsewhere, and published as images. The server only pulls and starts them.

```
  you push code ──► GitHub Actions builds the image ──► ghcr.io  ◄── ./scripts/update.sh (on the server)
```

## Deploy on any machine

1. **Prepare the machine.** On a new Hetzner (or any Ubuntu/Debian) server run `scripts/bootstrap.sh` as root. It installs Docker, adds swap, caps container logs, sets a firewall, turns on automatic security updates and switches SSH to keys only. Paste it into "user data" when creating the server and it runs by itself. On a machine that already has Docker (an OpenMediaVault tower) skip this.
2. **Get the stack there.** `git clone` this repo, or copy the folder.
3. **Fill in `.env`.** `cp .env.example .env`. Set `IMAGE_OWNER`, the three database passwords, `SITE_APP_SECRET` and the two domains. The file explains each one.
4. **Log in to the registry** if the images are private: `echo <token> | docker login ghcr.io -u <user> --password-stdin`. The token needs the `read:packages` scope.
5. **Start it.** `./scripts/update.sh`
6. **Finish in the apps.** Open `https://<ADMIN_DOMAIN>`. THRICE asks for a setup code, which is in `docker compose logs thrice-migrate`. The website's first admin and temporary password are in `docker compose logs site-migrate`.

No domain yet? Leave `ADMIN_DOMAIN` and `SITE_DOMAIN` blank. THRICE then answers on port 8080 and the website on 8081. Set `LAN_BIND=0.0.0.0` to reach them from other machines.

Behind a Cloudflare Tunnel: set `ADMIN_ADDR=http://admin.example.com` and `SITE_ADDR=http://example.com` and point the tunnel's public hostnames at `http://caddy:80` (or the machine's port 80). The tunnel does the HTTPS.

## Updating

```bash
./scripts/update.sh                  # apply whatever the tags in .env point to
./scripts/update.sh thrice=1.4.0     # deploy a specific THRICE version
./scripts/update.sh site=0.9.1       # deploy a specific website version
./scripts/update.sh rollback         # go back to the tags before the last version change
```

An update pulls the new images, restarts only what changed, waits for the apps to report healthy, and rolls back by itself if a version you named does not come up. Database changes run automatically when the app container starts. Take a backup first for any release that changes the database (the nightly one is fine).

How images get built: each app's repository has a workflow that publishes `ghcr.io/<owner>/<image>` when you push to `main` or tag a release (`git tag v1.4.0 && git push --tags`). Images:

- `ghcr.io/<owner>/thrice`
- `ghcr.io/<owner>/studio-site` and `ghcr.io/<owner>/studio-site-tools` (the website's app and its one-off migration job)

## Handy commands

```bash
docker compose logs -f thrice-app                 # watch THRICE
docker compose logs thrice-migrate                # THRICE setup code (first start only)
docker compose logs site-migrate                  # the website's first admin login
docker compose ps                                 # what is running
# Locked out of THRICE? Set a new random password for an account:
docker compose exec thrice-worker sh -c "cd apps/web && node_modules/.bin/tsx src/scripts/reset-password.ts owner@example.com"
```

## Demo data and moving real data in

- **Demo:** set `SITE_SEED_DEMO=true` before the first start for a made-up website, and choose "sample data" on THRICE's setup page. Nothing in either is real.
- **Real data:** in the apps that hold it (THRICE and the website) use **Data and backup** to download a backup file, then restore that file on the new install: on a fresh THRICE (after its setup page) and a fresh website (after its admin exists), before entering anything else. Both keep every id, and the website's photos travel in the file. `docs/DEPLOY.md` in each project has the command-line equivalents.

## Backups and restore

- The `backup` service writes `thrice-*.sql.gz`, `studio-*.sql.gz` and `media-*.tar.gz` to the `backups` volume every night and keeps `BACKUP_KEEP_DAYS` days.
- That volume sits on the same disk as the data. Copy it off the machine: set `COMPOSE_PROFILES=offsite` and the `RCLONE_*` settings (Backblaze B2, a Hetzner Storage Box over SFTP, S3, Drive and so on). Copies are added, never deleted from the remote.
- Restore one database: `./scripts/restore.sh thrice thrice-20260919-020000.sql.gz`. To restore the website's photos, extract `media-*.tar.gz` into the `site_media` volume.
- Practise a restore once, on a spare machine, before you need one.

## Moving to another server

Because everything is in Docker volumes and this folder: run `bootstrap.sh` on the new machine, copy `.env`, restore the latest backups with `restore.sh`, point DNS, and start. Nothing else is stored on the old server.

## Trying it on your own machine

`docker compose -f compose.yml -f compose.build.yml up -d --build` builds from the source folders next to this one (`../thrice`, `../setlet` — the studio website's dev folder) instead of pulling.

## Good to know

- Only Caddy publishes ports. The database and Redis sit on a network with no route to the internet.
- The Hetzner Cloud Firewall should allow only ports 22, 80 and 443. The server's own firewall (ufw) is a second layer, but Docker publishes its ports around it, so do not rely on ufw alone.
- Hetzner blocks outbound email ports 25 and 465 on new accounts. Use port 587 with STARTTLS for mail.
- Never put `.env` in git. It is already in `.gitignore`.
