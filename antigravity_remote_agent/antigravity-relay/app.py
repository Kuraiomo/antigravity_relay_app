import asyncio, os
from contextlib import asynccontextmanager
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

TOKEN = os.environ["RELAY_TOKEN"]
peers = {}
lock = asyncio.Lock()

@asynccontextmanager
async def lifespan(app):
    yield
    async with lock:
        peers.clear()

app = FastAPI(lifespan=lifespan)

@app.get("/health")
async def health():
    return {"ok": True, "service": "antigravity-relay"}

@app.websocket("/ws/{role}")
async def relay(ws: WebSocket, role: str):
    if role not in ("mobile", "desktop") or ws.headers.get("authorization") != f"Bearer {TOKEN}":
        await ws.close(code=1008, reason="Invalid role or unauthorized")
        return
    await ws.accept()
    async with lock:
        old = peers.get(role)
        peers[role] = ws
    if old and old is not ws:
        try: await old.close(code=4001, reason="Connection replaced")
        except Exception: pass
    try:
        while True:
            message = await ws.receive_text()
            if len(message.encode("utf-8")) > 131072:
                await ws.close(code=1009, reason="Message too large")
                break
            async with lock:
                target = peers.get("desktop" if role == "mobile" else "mobile")
            if target is None:
                await ws.send_json({"type":"relay_status","status":"peer_offline"})
            else:
                try: await target.send_text(message)
                except Exception:
                    await ws.send_json({"type":"relay_status","status":"delivery_failed"})
    except WebSocketDisconnect:
        pass
    finally:
        async with lock:
            if peers.get(role) is ws: peers.pop(role, None)
