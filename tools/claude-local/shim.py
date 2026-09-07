#!/usr/bin/env python3
"""claude-local shim: a tiny local proxy between Claude Code and a vLLM /v1/messages endpoint.

Why it exists
-------------
vLLM's Anthropic-compatible API (verified on 0.19.1) speaks the Messages API well enough for
Claude Code (streaming, tools, thinking, count_tokens) with two exceptions:

1. Claude Code appends `role: "system"` entries inside `messages` mid-conversation. vLLM only
   accepts `user` / `assistant` there and answers 400. Claude Code's automatic "retry without
   that capability" keys on Anthropic's error wording, which vLLM's pydantic error does not match.
   -> This shim folds every system-role entry into the adjacent user turn as text blocks.

2. vLLM errors (500) when `max_tokens` + prompt exceeds `max_model_len`, and Claude Code only
   compacts on a recognisable "prompt is too long" error.
   -> This shim counts the prompt via upstream /count_tokens, clamps `max_tokens` to what fits,
      and returns an Anthropic-style "prompt is too long" 400 when nothing fits, so Claude Code
      compacts instead of dying.

Everything else is forwarded byte-for-byte (headers, streaming SSE, error bodies).
Stdlib only. Listens on loopback only.

Configuration (environment; claude-local.ps1 sets these)
--------------------------------------------------------
UPSTREAM      upstream base URL            default: "upstream" in config.json next to this file
PORT          listen port on 127.0.0.1     default 8098
LOGDIR        log directory                default <this file's folder>/logs
CONTEXT_LEN   model context length         default: max_model_len from UPSTREAM/v1/models, else 65536
SHIM_DUMP     "1" dumps every request body to LOGDIR/req-N.json (debug only; contains conversation text)
"""
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))


def _load_config():
    try:
        with open(os.path.join(HERE, "config.json"), encoding="utf-8") as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return {}


_cfg = _load_config()
UPSTREAM = (os.environ.get("UPSTREAM") or _cfg.get("upstream") or "").rstrip("/")
PORT = int(os.environ.get("PORT", "8098"))
LOGDIR = os.environ.get("LOGDIR") or os.path.join(HERE, "logs")
DUMP = os.environ.get("SHIM_DUMP", "0") == "1"
SAFETY_MARGIN = 256          # tokens kept free between prompt + max_tokens and the context length
MIN_OUTPUT = 512             # below this many free tokens we report "prompt is too long" instead of generating
LOG_MAX_BYTES = 5 * 1024 * 1024

os.makedirs(LOGDIR, exist_ok=True)

# Under pythonw there is no console: send stdout/stderr to a file so nothing crashes on print().
if sys.stdout is None or sys.stderr is None:
    _err = open(os.path.join(LOGDIR, "shim.err"), "a", encoding="utf-8", buffering=1)
    sys.stdout = sys.stdout or _err
    sys.stderr = sys.stderr or _err

_lock = threading.Lock()
_counter = [0]
CONTEXT_LEN = None


def log(line: str):
    path = os.path.join(LOGDIR, "shim.log")
    with _lock:
        try:
            if os.path.exists(path) and os.path.getsize(path) > LOG_MAX_BYTES:
                os.replace(path, path + ".1")
        except OSError:
            pass
        with open(path, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + line + "\n")


def discover_context_len() -> int:
    forced = os.environ.get("CONTEXT_LEN")
    if forced:
        return int(forced)
    try:
        with urllib.request.urlopen(UPSTREAM + "/v1/models", timeout=5) as r:
            data = json.load(r).get("data") or []
            for m in data:
                if m.get("max_model_len"):
                    return int(m["max_model_len"])
    except Exception as e:  # noqa: BLE001
        log(f"context discovery failed ({e}); assuming 65536")
    return 65536


def _as_blocks(content):
    if content is None:
        return []
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return list(content)


def fold_system_messages(body: dict) -> int:
    """Fold role:'system' entries into the neighbouring user turn. Returns how many were folded."""
    msgs = body.get("messages")
    if not isinstance(msgs, list):
        return 0
    folded = 0
    out = []
    for m in msgs:
        if m.get("role") == "system":
            folded += 1
            blocks = _as_blocks(m.get("content"))
            if out and out[-1].get("role") == "user":
                out[-1] = {**out[-1], "content": _as_blocks(out[-1].get("content")) + blocks}
            else:
                out.append({"role": "user", "content": blocks})
        else:
            out.append(m)
    if folded:
        merged = []
        for m in out:
            if merged and merged[-1].get("role") == "user" and m.get("role") == "user":
                merged[-1] = {**merged[-1], "content": _as_blocks(merged[-1].get("content")) + _as_blocks(m.get("content"))}
            else:
                merged.append(m)
        body["messages"] = merged
    return folded


def count_prompt_tokens(body: dict, headers: dict):
    """Ask upstream how long the prompt is. Returns (tokens, exact)."""
    probe = {k: body[k] for k in ("model", "messages", "system", "tools") if k in body}
    data = json.dumps(probe).encode("utf-8")
    h = {k: v for k, v in headers.items() if k.lower() in ("authorization", "x-api-key", "anthropic-version")}
    h["content-type"] = "application/json"
    h["content-length"] = str(len(data))
    req = urllib.request.Request(UPSTREAM + "/v1/messages/count_tokens", data=data, headers=h, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return int(json.load(r).get("input_tokens")), True
    except Exception:  # noqa: BLE001
        # Rough fallback (marked "~" in the log): ~3 chars per token, deliberately pessimistic.
        return len(json.dumps(body)) // 3, False


def clamp_max_tokens(body: dict, headers: dict):
    """Returns (error_json_or_None, note). Mutates body['max_tokens'] when clamping."""
    t0 = time.time()
    prompt, exact = count_prompt_tokens(body, headers)
    tag = f"prompt{'=' if exact else '~'}{prompt}({(time.time() - t0) * 1000:.0f}ms)"
    free = CONTEXT_LEN - prompt - SAFETY_MARGIN
    if free < MIN_OUTPUT:
        msg = f"prompt is too long: {prompt} tokens > {CONTEXT_LEN - SAFETY_MARGIN - MIN_OUTPUT} maximum"
        return {"type": "error", "error": {"type": "invalid_request_error", "message": msg}}, f"{tag} TOO LONG"
    requested = int(body.get("max_tokens") or 0)
    if requested > free:
        body["max_tokens"] = free
        return None, f"{tag} max_tokens {requested}->{free}"
    return None, tag


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"  # close-delimited responses: simplest faithful relay of SSE streams

    def log_message(self, fmt, *args):  # silence default access log
        pass

    def _send_json(self, status: int, obj: dict):
        data = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_HEAD(self):  # Claude Code's best-effort /api/hello warm-up probe
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        self._forward(b"", None, "")

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        raw = self.rfile.read(length) if length else b""
        body = None
        try:
            body = json.loads(raw.decode("utf-8")) if raw else None
        except Exception:  # noqa: BLE001
            body = None
        note = ""
        path = self.path.split("?", 1)[0]
        if isinstance(body, dict) and path in ("/v1/messages", "/v1/messages/count_tokens"):
            with _lock:
                _counter[0] += 1
                n = _counter[0]
            if DUMP:
                with open(os.path.join(LOGDIR, f"req-{n}.json"), "w", encoding="utf-8") as f:
                    json.dump({"path": self.path, "headers": dict(self.headers.items()), "body": body}, f, indent=1, ensure_ascii=False)
            note += f" msgs={len(body.get('messages') or [])} tools={len(body.get('tools') or [])}"
            folded = fold_system_messages(body)
            if folded:
                note += f" folded_system={folded}"
            if path == "/v1/messages":
                err, cnote = clamp_max_tokens(body, dict(self.headers.items()))
                note += " " + cnote
                if err:
                    log(f"POST {path} model={body.get('model')}{note} => 400 (returned prompt-too-long to client)")
                    self._send_json(400, err)
                    return
            raw = json.dumps(body).encode("utf-8")
        self._forward(raw, body, note)

    def _forward(self, raw: bytes, body, note: str):
        fwd_headers = {k: v for k, v in self.headers.items()
                       if k.lower() not in ("host", "content-length", "connection", "transfer-encoding")}
        if raw:
            fwd_headers["content-length"] = str(len(raw))
        req = urllib.request.Request(UPSTREAM + self.path, data=raw or None, headers=fwd_headers, method=self.command)
        started = time.time()
        try:
            resp = urllib.request.urlopen(req, timeout=900)
        except urllib.error.HTTPError as e:
            resp = e
        except Exception as e:  # noqa: BLE001
            log(f"{self.command} {self.path}{note} => 502 upstream unreachable: {e}")
            self._send_json(502, {"type": "error", "error": {"type": "api_error",
                                                             "message": f"claude-local shim: upstream {UPSTREAM} unreachable ({e}). Is the server up and the VPN connected?"}})
            return
        status = resp.getcode()
        self.send_response(status)
        for k, v in resp.headers.items():
            if k.lower() in ("content-length", "transfer-encoding", "connection"):
                continue
            self.send_header(k, v)
        self.end_headers()
        first = b""
        total = 0
        try:
            while True:
                chunk = resp.read(4096)
                if not chunk:
                    break
                if not first:
                    first = chunk[:160]
                total += len(chunk)
                self.wfile.write(chunk)
                self.wfile.flush()
        except Exception as e:  # noqa: BLE001
            log(f"{self.command} {self.path}{note} => {status} relay aborted after {total}B: {e}")
            return
        summary = "" if status < 400 else " " + first.decode("utf-8", "replace").replace("\n", " ")[:160]
        model = body.get("model") if isinstance(body, dict) else ""
        stream = body.get("stream") if isinstance(body, dict) else ""
        log(f"{self.command} {self.path} model={model} stream={stream}{note} => {status} {total}B {time.time() - started:.1f}s{summary}")


def main():
    global CONTEXT_LEN
    if not UPSTREAM:
        log("no UPSTREAM: set the env var or put \"upstream\" in config.json next to shim.py")
        print("shim: no UPSTREAM configured", file=sys.stderr)
        sys.exit(2)
    CONTEXT_LEN = discover_context_len()
    with open(os.path.join(LOGDIR, "shim.pid"), "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))
    log(f"shim starting on 127.0.0.1:{PORT} -> {UPSTREAM} context_len={CONTEXT_LEN} pid={os.getpid()}")
    print(f"shim listening on 127.0.0.1:{PORT} -> {UPSTREAM} context_len={CONTEXT_LEN} logs={LOGDIR}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
