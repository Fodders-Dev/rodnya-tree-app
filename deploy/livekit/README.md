# LiveKit deploy

Rodnya uses a single-VM pilot layout for LiveKit on the current production host.

On the current VM, `Caddy` already occupies `443/udp` for HTTP/3, and embedded TURN/UDP was not stable on this shared host. The current working pilot therefore keeps embedded TURN on `TLS :5349` only, while LiveKit media still uses the normal WebRTC UDP range `50000-60000`.

## Layout

- `docker-compose.yml` runs:
  - `livekit/livekit-server`
  - local `redis`
- `network_mode: host` is used so LiveKit can expose WebRTC and TURN ports directly.
- TLS for `wss://livekit...` is terminated by `Caddy`.
- TLS for `turn...` is provided by LiveKit itself, using certificate files that Caddy has already issued for the TURN hostname.

## Expected production domains

- `livekit.rodnya-tree.ru` for HTTPS/WSS
- `turn.rodnya-tree.ru` for TURN/TLS

If DNS is not ready yet, a temporary `nip.io` hostname can be used for smoke tests, then replaced with the final Rodnya domains by updating `.env`, `livekit.yaml`, backend env, and the Caddyfile.

## Install on the server

1. Copy this directory to `/opt/rodnya/livekit`.
2. Copy `.env.example` to `.env` and replace the placeholder values.
3. Render `livekit.yaml` from the template:

```bash
set -a
source /opt/rodnya/livekit/.env
set +a
envsubst < /opt/rodnya/livekit/livekit.yaml.tmpl > /opt/rodnya/livekit/livekit.yaml
```

4. Install the systemd unit:

```bash
sudo install -m 0644 /opt/rodnya/livekit/rodnya-livekit.service /etc/systemd/system/rodnya-livekit.service
sudo systemctl daemon-reload
sudo systemctl enable --now rodnya-livekit.service
```

## Repeatable rollout from Windows

Use the repo helper from the project root:

```powershell
pwsh -File deploy/livekit/deploy_livekit.ps1 `
  -ServerHost 212.69.84.167 `
  -User root `
  -LiveKitHost livekit.rodnya-tree.ru `
  -TurnHost turn.rodnya-tree.ru
```

The helper packages `deploy/livekit/`, uploads it to the VM, updates Caddy and `/etc/rodnya-backend.env`, renders `livekit.yaml`, restarts `rodnya-livekit.service`, and checks that backend `/ready` exposes `liveKitEnabled=true`.

## Required firewall / public ports

- `80/tcp` for Caddy ACME
- `443/tcp` for Caddy HTTPS/WSS
- `5349/tcp` for TURN/TLS
- `7881/tcp` for ICE/TCP fallback
- `50000-60000/udp` for media

## Current host-specific config

The current production VM should pin LiveKit to the public NIC instead of relying on STUN auto-discovery across all host interfaces:

- `LIVEKIT_NODE_IP=212.69.84.167`
- `LIVEKIT_NETWORK_INTERFACE=ens1`

## Verification

```bash
sudo systemctl status rodnya-livekit.service --no-pager
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
curl -I https://livekit.rodnya-tree.ru
```
