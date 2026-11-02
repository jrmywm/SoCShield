"""Local, dependency-free browser UI for launching SoCShield RTL simulations."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import http.server
import json
import pathlib
import re
import subprocess
import sys
import threading
import urllib.parse
import webbrowser

ROOT = pathlib.Path(__file__).resolve().parents[1]
WEB = ROOT / "frontend"
RUNS = ROOT / "build" / "soc" / "frontend-runs"
LOCK = threading.Lock()
STATE = {"running": False, "run_id": None, "status": "idle", "message": "Ready", "started": None}
TASK = None


def read_metrics(run_dir: pathlib.Path):
    path = run_dir / "metrics.csv"
    if not path.is_file():
        return None
    with path.open(newline="", encoding="utf-8") as stream:
        row = next(csv.DictReader(stream), None)
    return row


def get_run(run_id: str):
    if not re.fullmatch(r"\d{8}-\d{6}-[0-9a-f]{6}", run_id):
        raise ValueError("Invalid run id")
    folder = (RUNS / run_id).resolve()
    if folder.parent != RUNS.resolve():
        raise ValueError("Invalid run path")
    manifest_path = folder / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else None
    metrics = read_metrics(folder)
    log_path = folder / "simulation.log"
    log = log_path.read_text(encoding="utf-8", errors="replace")[-12000:] if log_path.is_file() else ""
    events = []
    event_path = folder / "events.csv"
    if event_path.is_file():
        with event_path.open(newline="", encoding="utf-8") as stream:
            for row in csv.DictReader(stream):
                if row.get("event") in {"request", "response", "ack"}:
                    events.append({"cycle": int(row["cycle"]), "event": row["event"],
                                   "address": row.get("address", ""), "data": row.get("data", "")})
    return {"run_id": run_id, "metrics": metrics, "manifest": manifest, "log": log,
            "events": events, "waveform": f"/api/runs/{run_id}/waveform" if (folder / "soc.vcd").is_file() else None}


def execute_run(run_id: str, options: dict):
    global TASK
    run_dir = RUNS / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    command = [sys.executable, str(ROOT / "scripts" / "soc.py"), "--mode", str(options["mode"]),
               "--gap", str(options["gap"]), "--contention", str(options["contention"]),
               "--stall", str(options["stall"]), "--seed", str(options["seed"]),
               "--out", str(run_dir.relative_to(ROOT))]
    if options["trace"]:
        command.append("--trace")
    if options["random_stalls"]:
        command.append("--random-stalls")
    env = __import__("os").environ.copy()
    suite = ROOT / "tools" / "oss-cad-suite"
    env["PATH"] = str(suite / "bin") + __import__("os").pathsep + str(suite / "lib") + __import__("os").pathsep + env.get("PATH", "")
    log_path = run_dir / "dashboard-run.log"
    try:
        with log_path.open("w", encoding="utf-8") as log:
            proc = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    shell=False, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            with LOCK:
                STATE.update(running=True, run_id=run_id, status="running", message="Compiling firmware and running RTL simulation", started=dt.datetime.now(dt.timezone.utc).isoformat())
            code = proc.wait()
        sim_log = run_dir / "simulation.log"
        passed = code == 0 and sim_log.is_file() and "PASS soc" in sim_log.read_text(encoding="utf-8", errors="replace")
        with LOCK:
            STATE.update(running=False, status="passed" if passed else "failed",
                         message="Simulation passed" if passed else f"Simulation failed (exit {code}); inspect the run log", started=STATE["started"])
    except Exception as exc:
        with LOCK:
            STATE.update(running=False, status="failed", message=str(exc))


def validate_options(payload):
    if not isinstance(payload, dict):
        raise ValueError("Expected a JSON settings object")
    out = {}
    limits = {"mode": (0, 1), "gap": (0, 10000), "contention": (0, 1), "stall": (0, 100000), "seed": (1, 2147483647)}
    for key, (low, high) in limits.items():
        value = payload.get(key, 0 if key != "seed" else 1)
        if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
            raise ValueError(f"{key} must be an integer from {low} to {high}")
        out[key] = value
    for key in ("trace", "random_stalls"):
        value = payload.get(key, False)
        if not isinstance(value, bool):
            raise ValueError(f"{key} must be true or false")
        out[key] = value
    return out


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "SoCShieldDashboard/1.0"

    def log_message(self, *_):
        pass

    def send_bytes(self, body: bytes, mime: str, status=200):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' data:; font-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, value, status=200):
        self.send_bytes(json.dumps(value).encode("utf-8"), "application/json; charset=utf-8", status)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/":
            self.send_bytes((WEB / "index.html").read_bytes(), "text/html; charset=utf-8")
        elif path == "/app.css":
            self.send_bytes((WEB / "app.css").read_bytes(), "text/css; charset=utf-8")
        elif path == "/app.js":
            self.send_bytes((WEB / "app.js").read_bytes(), "text/javascript; charset=utf-8")
        elif path == "/api/status":
            with LOCK:
                self.send_json(dict(STATE))
        elif path.startswith("/api/runs/"):
            parts = path.split("/")
            try:
                data = get_run(parts[3])
                if len(parts) == 5 and parts[4] == "waveform":
                    wave = (RUNS / parts[3] / "soc.vcd").resolve()
                    if wave.parent != (RUNS / parts[3]).resolve() or not wave.is_file():
                        return self.send_json({"error": "Waveform not found"}, 404)
                    return self.send_bytes(wave.read_bytes(), "text/plain; charset=utf-8")
                self.send_json(data)
            except (ValueError, FileNotFoundError, json.JSONDecodeError) as exc:
                self.send_json({"error": str(exc)}, 404)
        else:
            self.send_json({"error": "Not found"}, 404)

    def do_POST(self):
        if urllib.parse.urlparse(self.path).path != "/api/runs":
            return self.send_json({"error": "Not found"}, 404)
        if self.client_address[0] not in {"127.0.0.1", "::1"}:
            return self.send_json({"error": "Local requests only"}, 403)
        origin = self.headers.get("Origin")
        if origin and origin not in {f"http://127.0.0.1:{self.server.server_port}", f"http://localhost:{self.server.server_port}"}:
            return self.send_json({"error": "Requests must come from this local dashboard"}, 403)
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 4096:
                raise ValueError("Invalid request size")
            options = validate_options(json.loads(self.rfile.read(length)))
        except (ValueError, json.JSONDecodeError) as exc:
            return self.send_json({"error": str(exc)}, 400)
        with LOCK:
            if STATE["running"]:
                return self.send_json({"error": "A simulation is already running", "run_id": STATE["run_id"]}, 409)
            run_id = dt.datetime.now().strftime("%Y%m%d-%H%M%S-") + __import__("secrets").token_hex(3)
            STATE.update(running=True, run_id=run_id, status="starting", message="Starting simulation", started=dt.datetime.now(dt.timezone.utc).isoformat())
            global TASK
            TASK = threading.Thread(target=execute_run, args=(run_id, options), daemon=True)
            TASK.start()
        self.send_json({"run_id": run_id, "status": "starting"}, 202)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--open", action="store_true", help="Open the local dashboard in a browser")
    args = parser.parse_args()
    if not WEB.is_dir() or not (ROOT / "tools/oss-cad-suite").is_dir():
        raise SystemExit("Frontend files or pinned OSS CAD Suite are missing")
    RUNS.mkdir(parents=True, exist_ok=True)
    # The simulation itself runs in a worker; a single-threaded HTTP server is
    # enough for this local UI and avoids shutdown races in bundled Python builds.
    server = http.server.HTTPServer(("127.0.0.1", args.port), Handler)
    print(f"SoCShield simulation dashboard: http://127.0.0.1:{args.port}")
    if args.open:
        threading.Timer(0.5, lambda: webbrowser.open(f"http://127.0.0.1:{args.port}")).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDashboard stopped")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
