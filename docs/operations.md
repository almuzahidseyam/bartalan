# Operation, backups, and recovery

## Start, stop, inspect

Use the Windows launcher files at the repository root, or the matching scripts under `scripts/`. The server needs a powered, awake PC and router. `restart: unless-stopped` restarts services when the Docker daemon starts; it does **not** configure Windows login/startup. After a reboot, run `Start-BartaLAN.cmd`. If the WSL IP changed, refresh the LAN portproxy as Administrator. Automatic startup and DHCP reservations are not configured by this project.

From WSL, the equivalent commands are:

```sh
cd /mnt/d/GitHub/bartalan
docker compose ps
docker compose logs --tail 50 mattermost
docker compose stop
docker compose up -d --pull never
```

Adjust the repository path if installed elsewhere. Do not run `docker compose down -v`: `-v` deletes persistent data. Removing/unregistering the BartaLAN WSL distribution also deletes its database and file volumes. Back up first.

## Administrator and users

The first administrator is created by `scripts/Bootstrap.ps1`; initial credentials are stored in `.secrets/admin.json`. That file is ignored by Git. Protect it with the Windows account's permissions and disk encryption. The `.env` database password is also private. Do not paste `docker compose config` or full environment output into public issues: rendered settings can contain passwords.

Create users with `scripts/Add-User.ps1`. The administrator can reset a local user's password through the local management CLI; from an interactive WSL terminal:

```sh
docker compose exec mattermost /mattermost/bin/mmctl --local user change-password USERNAME
```

Follow the interactive prompt. Check the installed CLI's `--help` if flags change. Email delivery, external authentication, and email verification are disabled; password recovery must remain local.

## Backup

```powershell
.\scripts\Backup.ps1
```

The backup script stops Mattermost briefly so files and the database are consistent, takes a custom-format PostgreSQL dump, archives the configuration and file volumes using an already-cached image with no network, and restarts Mattermost in a `finally` block. It does not stop PostgreSQL. Backups are under `backups/<UTC timestamp>/` and contain:

- `database.dump`: users, messages, permissions, metadata.
- `files.tar.gz`: attachments and local media.
- `config.tar.gz`: server configuration.
- `server.env`, optional `admin.json`: secrets and recovery settings.
- `manifest.json`: selected images, file hashes, creation time.

Treat a backup as private chat data. Copy it to a separate protected disk and test recovery before relying on the service. A failed backup directory may be incomplete and must not be used. Hashes detect accidental corruption; they do not encrypt a backup or authenticate who created it. Old backups are not automatically pruned.

## Recovery into a fresh test installation

Recover to an empty installation using the same pinned images first. Preserve the original runtime and backups. Do not restore over active data.

1. Verify every file against `manifest.json` before importing anything.
2. Prepare a fresh runtime/Compose project and load the required cached images. Copy `server.env` to its private `.env`; update the Compose project name and pilot address if needed so it cannot overlap the original server.
3. Start PostgreSQL alone: `docker compose up -d postgres`. Wait for it to become healthy.
4. Import `database.dump` with PostgreSQL's matching `pg_restore`, using the user/database from the restored `.env`. For example, in a Linux shell, use `docker compose exec -T postgres pg_restore -U <user> -d <database> --no-owner < /path/to/database.dump`. Do not include literal angle-bracket placeholders.
5. Create Mattermost's fresh volumes with `docker compose create mattermost`. Determine the actual volume names from `docker inspect` or `docker volume ls`; do not guess if multiple projects exist.
6. Restore each archive into its corresponding empty volume using a temporary cached PostgreSQL image, `--network none`, and `tar -xzf`. Preserve numeric owners, including Mattermost's UID 2000. Never unpack an untrusted archive as root.
7. Start Mattermost with `docker compose up -d --pull never`. Restore the private administrator credential file if needed. Check logins, old messages, file downloads, and live delivery on the recovery server before returning users to service.

The backup creation path is automated. The full recovery procedure is an operator runbook and must be rehearsed separately; a successfully created backup does not prove a complete restore.

## Cache images before an outage

```powershell
.\scripts\Export-Offline.ps1
```

This writes `offline-bundle/images.tar` and its SHA-256 checksum. On a prepared Docker host, verify the checksum, then load it with `docker image load -i images.tar`. The bundle is not a replacement for a WSL/Docker installer, and contains no messages or accounts. Keep compatible Desktop/Android installers separately before an outage, using official sources.

## Updates

The images are pinned by version and digest. Review upstream security releases while online. Back up, deliberately select and record new image digests, download them, test an upgrade on a copy, then apply to the active installation. The local server has no internet security-update checks; keeping the packages and images maintained is the operator's responsibility. Do not roll a database volume back to an older major PostgreSQL image.
