---
name: buzz-self-hosting
description: "Use when helping a user set up, debug, or operate a self-hosted Buzz relay through Docker Compose. Do not use for general Docker questions or non-Buzz Nostr deployments."
version: 1.0.0
metadata:
  hermes:
    tags: [buzz, self-hosting, relay, docker, compose, deployment, troubleshooting, nostr]
---

# Buzz Self-Hosting Guide

Walk the user through standing up their own `buzz-relay` with the Docker Compose stack in `deploy/compose/`, and debug it layer by layer when agents or clients misbehave. Every footgun in here was hit in a real setup; check them before inventing new theories.

Guide, don't drive: give the user paste-ready commands and let them run anything that changes state. Verify results yourself with read-only checks (logs, rosters, queries).

## The mental model

- **One relay = one community. The relay URL IS the community.** The relay routes connections to a community by the exact hostname in `BUZZ_DOMAIN`. A connection with any other Host gets **404 on the WebSocket upgrade** — this looks like "relay is down" but isn't.
- The stack is: relay + Postgres (events, search, memberships) + MinIO (media + git packfiles) + Redis (pub/sub only, nothing durable) + a git volume.
- On a **closed relay** (`RELAY_OWNER_PUBKEY` set, `BUZZ_REQUIRE_RELAY_MEMBERSHIP=true`), everything that connects — humans AND agents — must be in the relay member roster.

## Setup steps

1. `cd deploy/compose && cp .env.example .env`, then edit `.env`:
   - **Secrets are all generated/invented locally.** Nothing comes from a portal. `openssl rand -hex 32` for `BUZZ_RELAY_PRIVATE_KEY` and `BUZZ_GIT_HOOK_HMAC_SECRET`; invent Postgres/Redis/S3 passwords (Compose creates those services with whatever you set).
   - `RELAY_OWNER_PUBKEY` = the user's own pubkey, 64-char hex, from their Buzz Desktop profile. **Footgun: this var has no `BUZZ_` prefix** — easy to miss among neighbors that all do.
   - `BUZZ_RELAY_PRIVATE_KEY` is the relay's identity. Set once, never rotate; back up `.env` itself.
   - Pin `BUZZ_IMAGE` to a release tag for anything long-lived; `:main` moves daily.
2. Set the URL block (`BUZZ_DOMAIN`, `RELAY_URL`, `BUZZ_MEDIA_BASE_URL`, `BUZZ_MEDIA_SERVER_DOMAIN`, `BUZZ_CORS_ORIGINS`) — all derive from one host choice. See the localhost footgun below before choosing.
3. `./run.sh config` (validates; catches leftover CHANGE_ME), then `./run.sh start`. TLS on a public domain: `BUZZ_COMPOSE_TLS=true ./run.sh start`.
4. Liveness: `curl -fsS http://127.0.0.1:3000/_liveness`.
5. Register members: `./run.sh add-member <pubkey>` for every human and every agent, **with `sleep 1` between adds** (same-second roster events collide). Verify with `./run.sh list-members`.
6. Connect the desktop app with the exact `RELAY_URL`, create channels, add agents to channels, @mention.

## Footgun: never use `localhost` for a local relay — use `127.0.0.1` everywhere

`buzz-core::relay::normalize_relay_url` rewrites **every loopback host to `127.0.0.1`** (localhost, ::1). The desktop app runs each managed agent's relay URL through it before spawning the harness. The relay, however, routes by the literal `BUZZ_DOMAIN`. Result with `BUZZ_DOMAIN=localhost`: the app itself connects fine (its own HTTP client doesn't rewrite the Host header) but **every agent harness gets 404 and exits code 1**. The app UI offers no way around it — the per-agent `relay_url` field is deliberately ignored (agents always inherit the active workspace relay).

Therefore: for local deployments set `BUZZ_DOMAIN=127.0.0.1` and use `ws://127.0.0.1:3000` in the app and everywhere else. Real public domains are unaffected.

Diagnostic — test the host routing directly (`101` = good, `404` = wrong host):

```bash
curl -s -o /dev/null -w "%{http_code}\n" -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Sec-WebSocket-Version: 13" http://<host>:3000/
```

## Footgun: changing `BUZZ_DOMAIN` re-keys the community

The relay ensures its deployment community keyed to the host (`Deployment community ensured, host=...` in relay logs). Change the domain → restart → a **fresh empty community**. The desktop app will keep showing the old community's channels and member lists from cache — messages even still send (kind 9) — but channel records (39000/39002, 9007/9000) don't exist relay-side, so **agents discover 0 channels no matter what the UI shows**.

Fix: in the app, remove the community entirely and re-add it, then create channels fresh. Verify server-side, not in the UI:

```bash
docker compose --env-file .env -f compose.yml logs relay --since 10m | grep '"Event ingested via pipeline"'
```

Channel creation must produce kind `9007`/`40100` events; adding a member to a channel produces kind `9000`. If the user "did it in the app" but those kinds never arrive, the app state is stale — clean re-add.

## Debugging agents that don't respond — check layers in this order

Agent harness logs: `%APPDATA%\xyz.block.buzz.app\agents\logs\<agent-pubkey>__<relay-hash>.log` (Windows). Read the **newest** run — stale error banners in the app UI often describe an old failure.

| Log symptom | Layer | Fix |
|---|---|---|
| `relay connect failed ... 404 Not Found`, exit 1 | Hostname routing | `127.0.0.1` everywhere (see above) |
| Connects, but roster (`list-members`) lacks the agent | Relay membership | `./run.sh add-member <agent-pubkey>` |
| `discovered 0 channel(s) — agent will sit idle` | Channel membership | Add agent to a channel; verify a kind-9000 event lands; if UI says it's added but log still says 0 → stale community state, clean re-add |
| `discovered 1 channel(s)` + subscribed, mention ignored | respond_to | Default is `owner-only`; only the owner's mentions wake it |
| Wakes but errors instead of replying | Model auth | Per-runtime credentials (Hermes setup, Claude login, OpenAI key) — plumbing is fine |

Agent pubkeys and (plaintext!) private keys live in `%APPDATA%\xyz.block.buzz.app\agents\managed-agents.json` — treat as sensitive. The entries with `private_key_nsec` are the runtime records.

A healthy sequence in the harness log: `connected to relay` → `discovered N channel(s)` → `subscribed to channel <uuid>`; live adds show `membership notification: subscribing to new channel`.

## Windows-specific footguns

- `./run.sh` is bash. In PowerShell it opens the file in an editor instead of running. Use Git Bash (`/d/path` style paths) or `bash run.sh`.
- **Git Bash mangles container paths**: `docker compose exec relay /usr/local/bin/buzz-admin ...` becomes `C:/Program Files/Git/usr/local/bin/...` and fails with "OCI runtime exec failed". Fix: `export MSYS_NO_PATHCONV=1` first, or run docker commands from PowerShell.
- `$EDITOR .env` is a Unix-ism; PowerShell users should `notepad .env`.
- A file named `.env` looks nameless in Explorer unless "File name extensions" is on.
- If the app won't launch, check for hung instances: `Get-Process buzz-desktop, buzz-acp` — multiple Not-Responding `buzz-desktop` processes block new launches. Kill them all: `Get-Process buzz-desktop, buzz-acp -ErrorAction SilentlyContinue | Stop-Process -Force`.

## Verification & inspection

- Base stack exposes **only** relay port 3000. Admin surfaces need the dev overlay: `BUZZ_COMPOSE_DEV=true ./run.sh start` → MinIO console `:9001` (S3 creds from `.env`), Adminer `:8082` (server `postgres`, user `buzz`), Prometheus `:9090`. Home machines only — the overlay also publishes Postgres and Redis.
- Prove data is local: `docker compose --env-file .env -f compose.yml exec -T postgres psql -U buzz -d buzz -c "SELECT kind, left(content,60) FROM events WHERE kind=9 ORDER BY created_at DESC LIMIT 5;"`
- Postgres = the record (events partitioned by month, mention index, FTS, audit log, rosters). MinIO = media (content-addressed SHA-256) + git packfiles. Redis = disposable.

## Backups

Volumes live inside Docker Desktop's WSL2 disk — not browsable, not backed up until dumped to real files:

```powershell
copy .env <backup-dir>\env-backup.txt
docker compose --env-file .env -f compose.yml exec -T postgres pg_dump -U buzz buzz > <backup-dir>\buzz-db.sql
docker run --rm -v buzz-prod_buzz-minio-data:/data -v <backup-dir>:/backup alpine tar czf /backup/minio-data.tar.gz -C /data .
docker run --rm -v buzz-prod_buzz-git-data:/data -v <backup-dir>:/backup alpine tar czf /backup/git-data.tar.gz -C /data .
```

`.env` is part of the backup — restoring data volumes without its keys restores nothing.

## Hosted → self-hosted migration

There is no export tool. Identity keypairs carry over (same person everywhere); agent definitions are local files; **git repos migrate fully** (clone from hosted, push to new relay). Channel history, DMs, media, canvases do not. A new relay starts empty — set expectations before the user tears anything down, and don't remove hosted communities until anything worth keeping (repos, archives via `buzz messages get`) is pulled.
