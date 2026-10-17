# Antigravity WebSocket Relay

Minimal text relay for one mobile and one desktop connection. It forwards messages only; it does not control Antigravity or execute code.

## Deploy
Upload/extract this folder to `/opt/antigravity-relay`, then run:

```bash
cd /opt/antigravity-relay
python3 -c 'import secrets; print("RELAY_TOKEN=" + secrets.token_urlsafe(32))' > .env
chmod 600 .env
docker compose up -d --build
curl http://127.0.0.1:8765/health
```

Add `nginx-websocket-snippet.conf` inside the existing HTTPS server block for `websocket.pagepal.in`, then run `sudo nginx -t && sudo systemctl reload nginx`.

Endpoints: `wss://websocket.pagepal.in/ws/mobile` and `/ws/desktop`. Both clients must send `Authorization: Bearer <token from .env>` during handshake. Port 8765 is bound to localhost only. Keep the token secret. One active connection per role; a new one replaces the old one.
