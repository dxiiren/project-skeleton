#!/usr/bin/env python3
"""claude-local shim: a tiny local proxy between Claude Code and Anthropic-compatible model servers
(vLLM, Ollama) on one loopback port, routing each request to the endpoint its session chose.

Why it exists
-------------
vLLM's Anthropic-compatible API (verified on 0.19.1 and 0.26.0) speaks the Messages API well enough
for Claude Code (streaming, tools, thinking, count_tokens) with two exceptions:

1. Claude Code appends `role: "system"` entries inside `messages` mid-conversation. Older vLLM only
   accepts `user` / `assistant` there and answers 400, and Claude Code's automatic "retry without
   that capability" keys on Anthropic's error wording, which vLLM's pydantic error does not match.
   -> This shim folds every system-role entry into the adjacent user turn as text blocks.

2. vLLM errors (500) when `max_tokens` + prompt exceeds `max_model_len`, and Claude Code only
   compacts on a recognisable "prompt is too long" error.
   -> This shim counts the prompt via upstream /count_tokens (or estimates it when the server has
      no such endpoint), clamps `max_tokens` to what fits, and returns an Anthropic-style
      "prompt is too long" 400 when nothing fits, so Claude Code compacts instead of dying.

Everything else is forwarded byte-for-byte (headers, streaming SSE, error bodies).
Stdlib only. Listens on loopback only.

Routing
-------
claude-local.ps1 sets ANTHROPIC_CUSTOM_HEADERS so every Claude Code request carries
    x-claude-local-upstream: http://host:port      the endpoint this session chose
    x-claude-local-context:  65536                 its context length, when known
The shim routes on those (and strips them before forwarding). A request without them goes to the
default upstream, so one shim serves every endpoint and every concurrent session.

Configuration (environment; claude-local.ps1 sets these when it starts the shim)
------------------------------------------------------------------------------
UPSTREAM      default upstream base URL     default: the default endpoint in config.json next to this file
PORT          listen port on 127.0.0.1      default 8098
LOGDIR        log directory                 default <this file's folder>/logs
CONTEXT_LEN   context length of UPSTREAM    default: max_model_len from <upstream>/v1/models, else 65536
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
HDR_UPSTREAM = "x-claude-local-upstream"
HDR_CONTEXT = "x-claude-local-context"


def _load_config():
    try:
        with open(os.path.join(HERE, "config.json"), encoding="utf-8") as f:
            return json.load(f)
    except Exception:  # noqa: BLE001
        return {}


def _default_upstream(cfg: dict) -> str:
    eps = cfg.get("endpoints")
    if isinstance(eps, dict) and eps:
        name = cfg.get("default") or next(iter(eps))
        ep = eps.get(name) or next(iter(eps.values()))
        return (ep.get("upstream") or "").rstrip("/")
    return (cfg.get("upstream") or "").rstrip("/")


_cfg = _load_config()
UPSTREAM = (os.environ.get("UPSTREAM") or _default_upstream(_cfg)).rstrip("/")
PORT = int(os.environ.get("PORT", "8098"))
LOGDIR = os.environ.get("LOGDIR") or os.path.join(HERE, "logs")
DUMP = os.environ.get("SHIM_DUMP", "0") == "1"
SAFETY_MARGIN = 256          # tokens kept free between prompt + max_tokens and the context length
MIN_OUTPUT = 512             # below this many free tokens we report "prompt is too long" instead of generating
LOG_MAX_BYTES = 5 * 1024 * 1024
CHARS_PER_TOKEN = 3.6        # fallback estimate for servers without /count_tokens; real Claude Code request
                             # bodies measure 4.0 JSON chars per token on vLLM's counter, so this over-counts by ~12%

os.makedirs(LOGDIR, exist_ok=True)

# Under pythonw there is no console: send stdout/stderr to a file so nothing crashes on print().
if sys.stdout is None or sys.stderr is None:
    _err = open(os.path.join(LOGDIR, "shim.err"), "a", encoding="utf-8", buffering=1)
    sys.stdout = sys.stdout or _err
    sys.stderr = sys.stderr or _err

_lock = threading.Lock()
_counter = [0]
_context_cache = {}          # upstream -> context length
_no_count_endpoint = set()   # upstreams whose /count_tokens returned 404 (Ollama): estimate instead


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


def _short(upstream: str) -> str:
    return upstream.replace("http://", "").replace("https://", "")


def context_len_for(upstream: str, header_value=None) -> int:
    """Context length of an upstream: session header > cache > /v1/models max_model_len > 65536."""
    if header_value:
        try:
            n = int(header_value)
            if n > 0:
                _context_cache[upstream] = n
                return n
        except ValueError:
            pass
    if upstream in _context_cache:
        return _context_cache[upstream]
    n = 0
    try:
        with urllib.request.urlopen(upstream + "/v1/models", timeout=5) as r:
            for m in json.load(r).get("data") or []:
                if m.get("max_model_len"):
                    n = int(m["max_model_len"])
                    break
    except Exception as e:  # noqa: BLE001
        log(f"context discovery failed for {_short(upstream)} ({e})")
    if not n:
        n = 65536
        log(f"{_short(upstream)} does not report a context length; assuming {n} (set \"context\" for this endpoint in config.json)")
    _context_cache[upstream] = n
    return n


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


def estimate_tokens(body: dict) -> int:
    probe = {k: body[k] for k in ("messages", "system", "tools") if k in body}
    return int(len(json.dumps(probe)) / CHARS_PER_TOKEN)


def count_prompt_tokens(upstream: str, body: dict, headers: dict):
    """Ask upstream how long the prompt is. Returns (tokens, exact)."""
    if upstream in _no_count_endpoint:
        return estimate_tokens(body), False
    probe = {k: body[k] for k in ("model", "messages", "system", "tools") if k in body}
    data = json.dumps(probe).encode("utf-8")
    h = {k: v for k, v in headers.items() if k.lower() in ("authorization", "x-api-key", "anthropic-version")}
    h["content-type"] = "application/json"
    h["content-length"] = str(len(data))
    req = urllib.request.Request(upstream + "/v1/messages/count_tokens", data=data, headers=h, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return int(json.load(r).get("input_tokens")), True
    except urllib.error.HTTPError as e:
        if e.code in (404, 405, 501):
            _no_count_endpoint.add(upstream)
            log(f"{_short(upstream)} has no /count_tokens ({e.code}); estimating prompts at {CHARS_PER_TOKEN} chars/token from now on")
        return estimate_tokens(body), False
    except Exception:  # noqa: BLE001
        return estimate_tokens(body), False


def clamp_max_tokens(upstream: str, context_len: int, body: dict, headers: dict):
    """Returns (error_json_or_None, note). Mutates body['max_tokens'] when clamping."""
    t0 = time.time()
    prompt, exact = count_prompt_tokens(upstream, body, headers)
    tag = f"prompt{'=' if exact else '~'}{prompt}({(time.time() - t0) * 1000:.0f}ms)"
    free = context_len - prompt - SAFETY_MARGIN
    if free < MIN_OUTPUT:
        msg = f"prompt is too long: {prompt} tokens > {context_len - SAFETY_MARGIN - MIN_OUTPUT} maximum"
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

    def _route(self):
        """(upstream, context_len_or_None) for this request, from the session headers."""
        up = (self.headers.get(HDR_UPSTREAM) or UPSTREAM).rstrip("/")
        return up, self.headers.get(HDR_CONTEXT)

    def do_HEAD(self):  # Claude Code's best-effort /api/hello warm-up probe
        self.send_response(200)
        self.end_headers()

    def do_GET(self):
        if self.path.split("?", 1)[0] == "/shim/info":
            self._send_json(200, {"shim": "claude-local", "pid": os.getpid(), "port": PORT,
                                  "default_upstream": UPSTREAM, "contexts": _context_cache})
            return
        up, _ = self._route()
        self._forward(up, b"", None, "")

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
        up, ctx_hdr = self._route()
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
                context_len = context_len_for(up, ctx_hdr)
                err, cnote = clamp_max_tokens(up, context_len, body, dict(self.headers.items()))
                note += " " + cnote
                if err:
                    log(f"POST {path} up={_short(up)} model={body.get('model')}{note} => 400 (returned prompt-too-long to client)")
                    self._send_json(400, err)
                    return
            raw = json.dumps(body).encode("utf-8")
        self._forward(up, raw, body, note)

    def _forward(self, upstream: str, raw: bytes, body, note: str):
        skip = ("host", "content-length", "connection", "transfer-encoding", HDR_UPSTREAM, HDR_CONTEXT)
        fwd_headers = {k: v for k, v in self.headers.items() if k.lower() not in skip}
        if raw:
            fwd_headers["content-length"] = str(len(raw))
        req = urllib.request.Request(upstream + self.path, data=raw or None, headers=fwd_headers, method=self.command)
        started = time.time()
        try:
            resp = urllib.request.urlopen(req, timeout=900)
        except urllib.error.HTTPError as e:
            resp = e
        except Exception as e:  # noqa: BLE001
            log(f"{self.command} {self.path} up={_short(upstream)}{note} => 502 upstream unreachable: {e}")
            self._send_json(502, {"type": "error", "error": {"type": "api_error",
                                                             "message": f"claude-local shim: upstream {upstream} unreachable ({e}). Is the server up and the VPN connected?"}})
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
            log(f"{self.command} {self.path} up={_short(upstream)}{note} => {status} relay aborted after {total}B: {e}")
            return
        summary = "" if status < 400 else " " + first.decode("utf-8", "replace").replace("\n", " ")[:160]
        model = body.get("model") if isinstance(body, dict) else ""
        stream = body.get("stream") if isinstance(body, dict) else ""
        log(f"{self.command} {self.path} up={_short(upstream)} model={model} stream={stream}{note} => {status} {total}B {time.time() - started:.1f}s{summary}")


def main():
    if not UPSTREAM:
        log("no UPSTREAM: set the env var or configure an endpoint in config.json next to shim.py")
        print("shim: no UPSTREAM configured", file=sys.stderr)
        sys.exit(2)
    forced = os.environ.get("CONTEXT_LEN")
    if forced:
        _context_cache[UPSTREAM] = int(forced)
    with open(os.path.join(LOGDIR, "shim.pid"), "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))
    log(f"shim starting on 127.0.0.1:{PORT} default_upstream={_short(UPSTREAM)} context_len={context_len_for(UPSTREAM)} pid={os.getpid()}")
    print(f"shim listening on 127.0.0.1:{PORT} -> {UPSTREAM} logs={LOGDIR}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
