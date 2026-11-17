"""
Simulador: imita o ESP32 do autocarro e das paragens para testar sem hardware.

    python simulate.py                         # contra http://localhost:5000
    python simulate.py https://bus-alertas.onrender.com SEU_TOKEN
"""
import json, math, sys, time, urllib.request

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:5000").rstrip("/")
TOKEN = sys.argv[2] if len(sys.argv) > 2 else "MUDE_ESTE_TOKEN_2026"
RONIL = (-25.9641900, 32.5761100)
PANDORA = (-25.9663470, 32.5800335)

def post(path, body):
    req = urllib.request.Request(BASE + path, json.dumps(body).encode(),
                                 {"Content-Type": "application/json", "X-API-Token": TOKEN})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)

t = 0
while True:
    k = (math.sin(t / 20) + 1) / 2                     # vai e volta entre as duas paragens
    lat = RONIL[0] + (PANDORA[0] - RONIL[0]) * k
    lng = RONIL[1] + (PANDORA[1] - RONIL[1]) * k
    post("/api/telemetry", {"bus_code": "BUS-01", "latitude": lat, "longitude": lng, "gps_fix": 1, "led": 1})
    for code, near in (("RONIL", k < 0.03), ("PANDORA", k > 0.97)):
        ldr = 900 + int(200 * math.sin(t)) + (1500 if near else 0)
        r = post("/api/stop", {"stop_code": code, "ldr_value": ldr, "detected": 1 if near else 0, "bus_code": "BUS-01"})
        if r.get("alert_id"):
            print("CHEGADA ->", code, r)
    t += 1
    time.sleep(2)
