"""
Bus Alertas - servidor Flask.

Desenho pensado para hospedagem gratuita (Render + Neon):
  * Telemetria dos ESP32 (a cada 2 s) fica em MEMÓRIA -> rápido e não gasta a BD.
  * Só as CHEGADAS são gravadas na base de dados (raras).
  * O painel web e a app Android fazem polling a /api/state?since=<id>.

Correr localmente:
    pip install -r requirements.txt
    python app.py            -> http://localhost:5000
"""
from __future__ import annotations

import hmac
import math
import os
import threading
from datetime import datetime, timedelta, timezone

from flask import Flask, jsonify, render_template, request, send_from_directory
from sqlalchemy import (
    BigInteger, Column, DateTime, Integer, MetaData, String, Table,
    create_engine, desc, insert, select,
)

# ---------------------------------------------------------------------------
# Configuração (variáveis de ambiente)
# ---------------------------------------------------------------------------
API_TOKEN = os.environ.get("API_TOKEN", "MUDE_ESTE_TOKEN_2026")
ONLINE_SECONDS = int(os.environ.get("ONLINE_SECONDS", "12"))
DEDUP_SECONDS = int(os.environ.get("DEDUP_SECONDS", "20"))
HISTORY_SIZE = 100

STOPS = {
    "RONIL": {"nome": "Ronil", "latitude": -25.9641900, "longitude": 32.5761100},
    "PANDORA": {"nome": "Pandora", "latitude": -25.9663470, "longitude": 32.5800335},
}


def _db_url() -> str:
    url = os.environ.get("DATABASE_URL", "").strip()
    if not url:
        here = os.path.dirname(os.path.abspath(__file__))
        return "sqlite:///" + os.path.join(here, "bus_alertas.db")
    # Neon / Render dão "postgres://" ou "postgresql://"; SQLAlchemy + psycopg3:
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    if url.startswith("postgresql://"):
        url = "postgresql+psycopg://" + url[len("postgresql://"):]
    return url


engine = create_engine(_db_url(), pool_pre_ping=True, pool_recycle=280)
meta = MetaData()
alerts_table = Table(
    "alerts", meta,
    Column("id", BigInteger().with_variant(Integer, "sqlite"), primary_key=True, autoincrement=True),
    Column("stop_code", String(30), nullable=False, index=True),
    Column("bus_code", String(30)),
    Column("type", String(30), nullable=False, default="CHEGADA"),
    Column("message", String(255), nullable=False),
    Column("ldr_value", Integer),
    Column("created_at", DateTime, nullable=False, index=True),
)


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


def iso(value: datetime | None) -> str | None:
    return value.strftime("%Y-%m-%dT%H:%M:%SZ") if value else None


# ---------------------------------------------------------------------------
# Estado em memória
# ---------------------------------------------------------------------------
lock = threading.Lock()
buses: dict[str, dict] = {}
stops: dict[str, dict] = {
    code: {**cfg, "codigo": code, "ldr_value": 0, "detected": False, "last_seen": None}
    for code, cfg in STOPS.items()
}
history: list[dict] = []          # últimos alertas (mais recente no fim)


def _row_to_alert(row) -> dict:
    m = row._mapping
    stop = STOPS.get(m["stop_code"], {})
    return {
        "id": int(m["id"]),
        "stop_code": m["stop_code"],
        "stop_name": stop.get("nome", m["stop_code"]),
        "bus_code": m["bus_code"],
        "type": m["type"],
        "message": m["message"],
        "ldr_value": m["ldr_value"],
        "created_at": iso(m["created_at"]),
        "_ts": m["created_at"],
    }


def init_storage() -> None:
    meta.create_all(engine)
    with engine.connect() as conn:
        rows = conn.execute(
            select(alerts_table).order_by(desc(alerts_table.c.id)).limit(HISTORY_SIZE)
        ).fetchall()
    history.extend(_row_to_alert(r) for r in reversed(rows))
    for alert in history:
        if alert["stop_code"] in stops:
            stops[alert["stop_code"]]["last_arrival"] = alert["created_at"]
            stops[alert["stop_code"]]["last_bus"] = alert["bus_code"]


def public_alert(a: dict) -> dict:
    return {k: v for k, v in a.items() if not k.startswith("_")}


def haversine_m(lat1, lon1, lat2, lon2) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = Flask(__name__)
app.json.ensure_ascii = False
app.json.sort_keys = False


@app.after_request
def cors(resp):
    # A app Android e páginas externas podem ler a API pública.
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type, X-API-Token"
    if request.path.startswith("/api/"):
        resp.headers["Cache-Control"] = "no-store"
    return resp


def payload() -> dict:
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else request.form.to_dict()


def token_ok(data: dict) -> bool:
    token = request.headers.get("X-API-Token") or str(data.get("token", ""))
    return hmac.compare_digest(API_TOKEN.encode(), token.encode())


def truthy(v) -> bool:
    return str(v).strip().lower() in {"1", "true", "on", "yes"}


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/sw.js")
def service_worker():
    resp = send_from_directory(app.static_folder, "sw.js")
    resp.headers["Service-Worker-Allowed"] = "/"
    resp.headers["Cache-Control"] = "no-cache"
    return resp


@app.get("/health")
def health():
    return jsonify(ok=True, time=iso(utcnow()))


# --- ESP32 do autocarro ------------------------------------------------------
@app.post("/api/telemetry")
@app.post("/api/telemetry.php")          # compatibilidade com o firmware antigo
def telemetry():
    data = payload()
    if not token_ok(data):
        return jsonify(ok=False, error="Token inválido"), 401

    code = str(data.get("bus_code") or "BUS-01").strip()[:30]
    fix = truthy(data.get("gps_fix"))
    try:
        lat = float(data.get("latitude")) if fix else None
        lng = float(data.get("longitude")) if fix else None
    except (TypeError, ValueError):
        lat = lng = None
        fix = False

    now = utcnow()
    with lock:
        bus = buses.setdefault(code, {"codigo": code, "latitude": None, "longitude": None})
        if fix and lat is not None:
            prev = (bus.get("latitude"), bus.get("longitude"), bus.get("_fix_time"))
            if prev[0] is not None and prev[2]:
                dt_s = (now - prev[2]).total_seconds()
                if 0 < dt_s < 30:
                    speed = haversine_m(prev[0], prev[1], lat, lng) / dt_s * 3.6
                    bus["speed_kmh"] = round(speed, 1) if speed < 150 else bus.get("speed_kmh")
            bus.update(latitude=lat, longitude=lng, _fix_time=now)
        bus.update(gps_fix=fix, led_status=truthy(data.get("led", 1)), last_seen=now)

    return jsonify(ok=True, bus_code=code, server_time=iso(now))


# --- ESP32 das paragens ------------------------------------------------------
@app.post("/api/stop")
@app.post("/api/stop.php")
def stop_update():
    data = payload()
    if not token_ok(data):
        return jsonify(ok=False, error="Token inválido"), 401

    code = str(data.get("stop_code", "")).strip().upper()
    if code not in stops:
        return jsonify(ok=False, error="Paragem inválida"), 400

    try:
        ldr = int(float(data.get("ldr_value", 0)))
    except (TypeError, ValueError):
        ldr = 0
    detected = truthy(data.get("detected"))
    bus_code = str(data.get("bus_code") or "BUS-01").strip()[:30]
    now = utcnow()
    created = None

    with lock:
        stop = stops[code]
        stop.update(ldr_value=ldr, detected=detected, last_seen=now)
        if detected:
            recent = any(
                a["stop_code"] == code and (now - a["_ts"]).total_seconds() < DEDUP_SECONDS
                for a in history[-10:]
            )
            if not recent:
                msg = f"Autocarro {bus_code} chegou à paragem {stop['nome']}"
                with engine.begin() as conn:
                    res = conn.execute(insert(alerts_table).values(
                        stop_code=code, bus_code=bus_code, type="CHEGADA",
                        message=msg, ldr_value=ldr, created_at=now,
                    ))
                    new_id = int(res.inserted_primary_key[0])
                created = {
                    "id": new_id, "stop_code": code, "stop_name": stop["nome"],
                    "bus_code": bus_code, "type": "CHEGADA", "message": msg,
                    "ldr_value": ldr, "created_at": iso(now), "_ts": now,
                }
                history.append(created)
                del history[:-HISTORY_SIZE]
                stop["last_arrival"] = created["created_at"]
                stop["last_bus"] = bus_code

    return jsonify(ok=True, stop_code=code, detected=detected,
                   alert_id=created["id"] if created else None)


# --- Leitura pública (painel + app Android) ----------------------------------
@app.get("/api/state")
@app.get("/api/state.php")
def state():
    try:
        since = int(request.args["since"]) if "since" in request.args else None
    except ValueError:
        since = None
    now = utcnow()
    today = now - timedelta(hours=24)

    def online(ts):
        return bool(ts and (now - ts).total_seconds() <= ONLINE_SECONDS)

    with lock:
        bus_list = [{
            "codigo": b["codigo"], "latitude": b.get("latitude"), "longitude": b.get("longitude"),
            "gps_fix": b.get("gps_fix", False), "led_status": b.get("led_status", False),
            "speed_kmh": b.get("speed_kmh"), "last_seen": iso(b.get("last_seen")),
            "online": online(b.get("last_seen")),
        } for b in buses.values()]

        stop_list = []
        for s in stops.values():
            item = {
                "codigo": s["codigo"], "nome": s["nome"],
                "latitude": s["latitude"], "longitude": s["longitude"],
                "ldr_value": s["ldr_value"], "detected": s["detected"],
                "last_seen": iso(s["last_seen"]), "online": online(s["last_seen"]),
                "last_arrival": s.get("last_arrival"), "last_bus": s.get("last_bus"),
                "distance_m": None,
            }
            fixed = [b for b in bus_list if b["latitude"] is not None]
            if fixed:
                item["distance_m"] = round(min(
                    haversine_m(b["latitude"], b["longitude"], s["latitude"], s["longitude"])
                    for b in fixed
                ))
            stop_list.append(item)

        alerts = [public_alert(a) for a in reversed(history[-30:])]
        new_alerts = [public_alert(a) for a in history if a["id"] > since] if since is not None else []
        arrivals_24h = sum(1 for a in history if a["_ts"] >= today)
        last_id = history[-1]["id"] if history else 0

    return jsonify(
        ok=True, server_time=iso(now), last_id=last_id,
        stats={
            "buses_online": sum(1 for b in bus_list if b["online"]),
            "buses_total": len(bus_list),
            "stops_online": sum(1 for s in stop_list if s["online"]),
            "stops_total": len(stop_list),
            "arrivals_24h": arrivals_24h,
        },
        buses=bus_list, stops=stop_list, alerts=alerts, new_alerts=new_alerts,
    )


init_storage()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), debug=False, threaded=True)
