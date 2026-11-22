#!/usr/bin/env python3
"""Gemini API -> OpenAI chat-completions bridge, used by `agy-copilot`.

agy (Antigravity CLI) in API-key mode speaks only Gemini's native protocol,
which copilot-proxy does not serve. copilot-route.sh starts one bridge per agy
session on a free loopback port. The bridge translates each request and
forwards it to copilot-proxy's /v1/chat/completions. Routes (the /v1beta
prefix is optional):

  POST /v1beta/models/{model}:streamGenerateContent?alt=sse   (what agy uses)
  POST /v1beta/models/{model}:generateContent
  POST /v1beta/models/{model}:countTokens                     (rough estimate)

The translation is adapted from LiteLLM v1.99.4,
litellm/google_genai/adapters/transformation.py (pinned as the submodule
third_party/litellm). Changes from upstream, each one needed for agy:
  - functionResponse is read from any role. agy sends tool results as role
    "model"; upstream drops them there, and Copilot then rejects the request
    because the tool call has no result.
  - Tool-call ids round-trip via functionCall.id / functionResponse.id, which
    agy echoes. Upstream uses call_<name>, which collides on repeated calls.
  - reasoning_text streams back as thought parts. reasoning_opaque round-trips
    as the part's thoughtSignature. Thought parts are dropped from history.
  - camelCase inlineData (agy is built on the Go SDK), multi-part
    systemInstruction, thinkingConfig -> reasoning_effort, max_tokens clamped
    to the model's limit, usage including thought and cached tokens.
  - Tool calls are emitted once, at the end of a stream that finished
    cleanly, instead of as soon as the partial arguments happen to parse as
    JSON. A stream that errors or ends before finish_reason, or whose
    arguments don't parse, ends with a Gemini error event (503 UNAVAILABLE,
    which agy retries) and no tool calls, so a cut-off turn never runs a tool.
  - A user message (e.g. an image from a tool result) never splits one
    assistant turn's tool results; OpenAI requires them back to back.

It is also agy's HTTPS proxy (copilot-route.sh sets HTTPS_PROXY for the
session). CONNECT tunnels go through to any host except BLOCKED_HOSTS: agy
uploads ~43 KB of usage logs to play.googleapis.com per short session, with
"Enable Telemetry" off too (measured on agy 1.5.14). Commands agy runs inherit
the proxy, so they keep working through the tunnel. Every CONNECT is logged.

Configuration comes from the environment, never argv, so keys stay out of ps:
  BRIDGE_KEY          key agy must send (x-goog-api-key, ?key=, or Bearer)
  UPSTREAM_URL        copilot-proxy base URL, e.g. http://127.0.0.1:6868
  UPSTREAM_KEY        copilot-proxy key
  BRIDGE_MODEL        Copilot model for agy's requests
  BRIDGE_SMALL_MODEL  Copilot model when agy names a flash/lite model
  BRIDGE_PORT_FILE    the bound port is written here once listening
  BRIDGE_PORT         optional fixed port (default: chosen by the kernel)
Log lines go to stderr; copilot-route.sh appends them to agy-bridge.log.

Portions adapted from LiteLLM: Copyright (c) 2023 Berri AI, MIT License.

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
"""
from __future__ import annotations

import base64
import hmac
import http.client
import json
import os
import re
import select
import signal
import socket
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

ROUTE = re.compile(r"^/(?:v1beta/)?models/([^/:]+):(streamGenerateContent|generateContent|countTokens)$")
FINISH = {"stop": "STOP", "tool_calls": "STOP", "function_call": "STOP",
          "length": "MAX_TOKENS", "content_filter": "SAFETY"}
STATUS = {400: "INVALID_ARGUMENT", 401: "UNAUTHENTICATED", 403: "PERMISSION_DENIED",
          404: "NOT_FOUND", 429: "RESOURCE_EXHAUSTED", 503: "UNAVAILABLE"}

BLOCKED_HOSTS = frozenset({"play.googleapis.com"})

CFG: dict[str, str] = {}
CATALOG: dict[str, dict] = {}  # Copilot model id -> {"max_output": int|None, "efforts": [str]}


class UpstreamFailed(Exception):
    """The upstream turn did not complete; nothing from it may be acted on."""


def log(msg: str) -> None:
    print(time.strftime("%Y-%m-%dT%H:%M:%S"), f"[{os.getpid()}]", msg, file=sys.stderr, flush=True)


def upstream(path: str, payload: dict | None = None, timeout: float = 600):
    req = urllib.request.Request(
        CFG["UPSTREAM_URL"] + path,
        data=None if payload is None else json.dumps(payload).encode(),
        headers={"Authorization": "Bearer " + CFG["UPSTREAM_KEY"], "Content-Type": "application/json"},
    )
    return DIRECT.open(req, timeout=timeout)


# Never route the hop to copilot-proxy through a proxy from the environment.
DIRECT = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def load_catalog() -> dict[str, dict]:
    try:
        with upstream("/v1/models", timeout=10) as resp:
            models = json.load(resp)["data"]
    except (OSError, ValueError, KeyError) as e:
        log(f"model catalog unavailable ({e}); no passthrough, no max_tokens clamp")
        return {}
    catalog = {}
    for m in models:
        caps = m.get("capabilities") or {}
        catalog[m["id"]] = {"max_output": (caps.get("limits") or {}).get("max_output_tokens"),
                            "efforts": (caps.get("supports") or {}).get("reasoning_effort") or []}
    return catalog


def pick_model(requested: str) -> str:
    if requested in CATALOG:
        return requested
    small = "flash" in requested or "lite" in requested
    return CFG["BRIDGE_SMALL_MODEL"] if small else CFG["BRIDGE_MODEL"]


def reasoning_effort(gen_config: dict, model: str) -> str | None:
    thinking = gen_config.get("thinkingConfig") or {}
    level = str(thinking.get("thinkingLevel") or "").lower()
    if level:
        effort = "low" if level == "minimal" else level
    elif "thinkingBudget" in thinking:
        budget = thinking["thinkingBudget"]  # agy: --effort low -> 1024, high -> -1 (dynamic)
        effort = "high" if budget < 0 or budget > 8192 else "medium" if budget > 1024 else "low"
    else:
        return None
    supported = (CATALOG.get(model) or {}).get("efforts")
    return effort if not supported or effort in supported else None


# ── Gemini request -> OpenAI request ──────────────────────────────────────

def wrap_signature(opaque: str) -> str:
    # thoughtSignature is bytes (base64 in JSON); reasoning_opaque is an
    # arbitrary string, so encode it rather than trust it to be valid base64.
    return base64.b64encode(opaque.encode()).decode()


def unwrap_signature(sig: str) -> str | None:
    try:
        return base64.b64decode(sig).decode()
    except ValueError:
        return None


def tool_output(response) -> str:
    if isinstance(response, dict) and len(response) == 1:
        (only,) = response.values()
        if isinstance(only, str):
            return only  # agy sends {"output": "..."}; unwrapped, it isn't re-escaped
    return json.dumps(response if response is not None else {})


def media_part(part: dict) -> dict | None:
    data = part.get("inlineData") or part.get("inline_data")
    if not data:
        return None
    mime = data.get("mimeType") or data.get("mime_type") or "application/octet-stream"
    if not mime.startswith("image/"):
        return {"type": "text", "text": f"[gemini_bridge: {mime} attachment omitted; only images pass through]"}
    return {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{data.get('data', '')}"}}


def take_call_id(state: dict, name: str) -> str:
    for i, (queued_name, call_id) in enumerate(state["queue"]):
        if queued_name == name:
            return state["queue"].pop(i)[1]
    return f"call_bridge_orphan_{name}"


def content_to_messages(content: dict, state: dict) -> list[dict]:
    role = content.get("role") or "user"
    texts, media, calls, results, opaque = [], [], [], [], None
    for part in content.get("parts") or []:
        if opaque is None and part.get("thoughtSignature"):
            opaque = unwrap_signature(part["thoughtSignature"])
        if part.get("thought"):
            continue
        if "functionCall" in part:
            fc = part["functionCall"]
            call_id = fc.get("id")
            if not call_id:
                state["n"] += 1
                call_id = f"call_bridge_{state['n']}"
                state["queue"].append((fc.get("name"), call_id))
            calls.append({"id": call_id, "type": "function",
                          "function": {"name": fc.get("name", ""), "arguments": json.dumps(fc.get("args") or {})}})
        elif "functionResponse" in part:
            fr = part["functionResponse"]
            call_id = fr.get("id") or take_call_id(state, fr.get("name"))
            results.append({"role": "tool", "tool_call_id": call_id, "content": tool_output(fr.get("response"))})
            media.extend(m for m in map(media_part, fr.get("parts") or []) if m)
        elif "text" in part:
            texts.append(part["text"])
        else:
            m = media_part(part)
            if m:
                media.append(m)

    out = []
    if role == "model" and (texts or calls):
        msg = {"role": "assistant", "content": "".join(texts) or None}
        if calls:
            msg["tool_calls"] = calls
        if opaque:
            msg["reasoning_opaque"] = opaque
        out.append(msg)
    out.extend(results)  # tool results must directly follow the assistant tool_calls
    user_parts = ([] if role == "model" else [{"type": "text", "text": t} for t in texts]) + media
    if user_parts:
        only_text = len(user_parts) == 1 and user_parts[0]["type"] == "text"
        out.append({"role": "user", "content": user_parts[0]["text"] if only_text else user_parts})
    return out


def to_openai(body: dict, model: str) -> dict:
    messages = []
    system = "\n\n".join(p["text"] for p in (body.get("systemInstruction") or {}).get("parts") or [] if p.get("text"))
    if system:
        messages.append({"role": "system", "content": system})
    state = {"n": 0, "queue": []}
    unanswered, held = set(), []
    for content in body.get("contents") or []:
        for msg in content_to_messages(content, state):
            if msg["role"] == "assistant":
                messages.extend(held)
                held = []
                unanswered = {call["id"] for call in msg.get("tool_calls") or []}
                messages.append(msg)
            elif msg["role"] == "tool":
                unanswered.discard(msg["tool_call_id"])
                messages.append(msg)
                if not unanswered:
                    messages.extend(held)
                    held = []
            elif unanswered:
                held.append(msg)
            else:
                messages.append(msg)
    messages.extend(held)
    req = {"model": model, "messages": messages}

    tools = []
    for tool in body.get("tools") or []:
        for decl in tool.get("functionDeclarations") or []:
            fn = {"name": decl.get("name", "")}
            if decl.get("description"):
                fn["description"] = decl["description"]
            params = decl.get("parametersJsonSchema") or decl.get("parameters")
            if params:
                fn["parameters"] = params
            tools.append({"type": "function", "function": fn})
    if tools:
        req["tools"] = tools
        mode = ((body.get("toolConfig") or {}).get("functionCallingConfig") or {}).get("mode")
        if mode in ("ANY", "NONE"):
            req["tool_choice"] = "required" if mode == "ANY" else "none"

    gen = body.get("generationConfig") or {}
    for src, dst in (("temperature", "temperature"), ("topP", "top_p"),
                     ("stopSequences", "stop"), ("maxOutputTokens", "max_tokens")):
        if src in gen:
            req[dst] = gen[src]
    cap = (CATALOG.get(model) or {}).get("max_output")
    if cap and req.get("max_tokens", 0) > cap:
        req["max_tokens"] = cap
    effort = reasoning_effort(gen, model)
    if effort:
        req["reasoning_effort"] = effort
    return req


# ── OpenAI response -> Gemini response ────────────────────────────────────

def usage_metadata(usage: dict | None) -> dict:
    u = usage or {}
    prompt, completion = u.get("prompt_tokens") or 0, u.get("completion_tokens") or 0
    thoughts = u.get("reasoning_tokens") or (u.get("completion_tokens_details") or {}).get("reasoning_tokens") or 0
    cached = (u.get("prompt_tokens_details") or {}).get("cached_tokens") or 0
    meta = {"promptTokenCount": prompt, "candidatesTokenCount": max(completion - thoughts, 0),
            "totalTokenCount": u.get("total_tokens") or prompt + completion}
    if thoughts:
        meta["thoughtsTokenCount"] = thoughts
    if cached:
        meta["cachedContentTokenCount"] = cached
    return meta


class Turn:
    """One completion, streamed or not, accumulated into Gemini parts."""

    def __init__(self, include_thoughts: bool):
        self.include_thoughts = include_thoughts
        self.calls: dict[int, dict] = {}
        self.opaque = ""
        self.finish: str | None = None
        self.usage: dict | None = None

    def feed(self, delta: dict) -> list[dict]:
        """Take a stream delta (or a whole message); return the text parts to emit now."""
        parts = []
        if self.include_thoughts and delta.get("reasoning_text"):
            parts.append({"text": delta["reasoning_text"], "thought": True})
        if delta.get("content"):
            parts.append({"text": delta["content"]})
        self.opaque += delta.get("reasoning_opaque") or ""
        for i, tc in enumerate(delta.get("tool_calls") or []):
            acc = self.calls.setdefault(tc.get("index", i), {"id": "", "name": "", "arguments": ""})
            fn = tc.get("function") or {}
            acc["id"] = tc.get("id") or acc["id"]
            acc["name"] = fn.get("name") or acc["name"]
            acc["arguments"] += fn.get("arguments") or ""
        return parts

    def call_parts(self) -> list[dict]:
        parts = []
        for _, call in sorted(self.calls.items()):
            try:
                args = json.loads(call["arguments"] or "{}")
            except ValueError:
                raise UpstreamFailed(f"unparseable arguments for {call['name']}: {call['arguments'][:200]!r}")
            fc = {"name": call["name"], "args": args}
            if call["id"]:
                fc["id"] = call["id"]
            parts.append({"functionCall": fc})
        if parts and self.opaque:
            parts[0]["thoughtSignature"] = wrap_signature(self.opaque)
        return parts

    def response(self, parts: list[dict], final: bool = False) -> dict:
        candidate = {"content": {"role": "model", "parts": parts}, "index": 0}
        out = {"candidates": [candidate]}
        if final:
            candidate["finishReason"] = FINISH.get(self.finish, "STOP") if self.finish else "OTHER"
            out["usageMetadata"] = usage_metadata(self.usage)
        return out


def gemini_events(lines, turn: Turn):
    """Gemini stream events for an upstream chat/completions SSE body.

    Raises UpstreamFailed if the upstream reports an error or stops before a
    finish_reason. Text already sent stands, but tool calls are only emitted
    at the end of a turn that finished.
    """
    for raw in lines:
        line = raw.decode("utf-8", errors="replace").strip()
        if not line.startswith("data:"):
            continue
        data = line[len("data:"):].strip()
        if data == "[DONE]":
            break
        try:
            chunk = json.loads(data)
        except ValueError:
            log(f"skipping malformed upstream SSE line: {data[:200]!r}")
            continue
        if chunk.get("error"):
            raise UpstreamFailed(f"upstream error mid-stream: {json.dumps(chunk['error'])[:300]}")
        turn.usage = chunk.get("usage") or turn.usage
        for choice in chunk.get("choices") or []:
            turn.finish = choice.get("finish_reason") or turn.finish
            parts = turn.feed(choice.get("delta") or {})
            if parts:
                yield turn.response(parts)
    if not turn.finish:
        raise UpstreamFailed("upstream stream ended before finish_reason")
    yield turn.response(turn.call_parts(), final=True)


# ── HTTP ──────────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args) -> None:
        pass  # one summary line per request is logged in do_POST instead

    def do_GET(self) -> None:
        self.fail(404, f"no route for GET {urlsplit(self.path).path}")

    def do_CONNECT(self) -> None:
        host, _, port = self.path.rpartition(":")
        if host.lower().rstrip(".") in BLOCKED_HOSTS:
            log(f"proxy: blocked CONNECT {self.path}")
            return self.fail(403, f"gemini_bridge blocks {host}")
        try:
            remote = socket.create_connection((host, int(port)), timeout=30)
        except (OSError, ValueError) as e:
            log(f"proxy: CONNECT {self.path} failed: {e}")
            return self.fail(502, f"cannot reach {self.path}: {e}")
        log(f"proxy: CONNECT {self.path}")
        self.send_response(200, "Connection Established")
        self.end_headers()
        with remote:
            remote.settimeout(None)
            pipe(self.connection, remote)

    def do_POST(self) -> None:
        url = urlsplit(self.path)
        match = ROUTE.match(url.path)
        if not match:
            return self.fail(404, f"no route for POST {url.path}")
        if not self.authorized(url):
            return self.fail(401, "missing or wrong API key")
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        except ValueError as e:
            return self.fail(400, f"invalid JSON body: {e}")

        requested, method = match.groups()
        if method == "countTokens":
            return self.send_json(200, {"totalTokens": len(json.dumps(body)) // 4})

        model = pick_model(requested)
        stream = method == "streamGenerateContent"
        req = to_openai(body, model)
        if stream:
            req["stream"] = True
            req["stream_options"] = {"include_usage": True}
        thinking = (body.get("generationConfig") or {}).get("thinkingConfig") or {}
        turn = Turn(include_thoughts=bool(thinking.get("includeThoughts")))

        started = time.time()
        try:
            resp = upstream("/v1/chat/completions", req)
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:2000]
            log(f"{requested} -> {model}: upstream HTTP {e.code}: {detail[:300]}")
            return self.fail(e.code, f"copilot-proxy ({model}): {detail}")
        except OSError as e:
            log(f"{requested} -> {model}: upstream unreachable: {e}")
            return self.fail(503, f"copilot-proxy unreachable at {CFG['UPSTREAM_URL']}: {e}")

        try:
            with resp:
                if stream:
                    self.relay_stream(resp, turn)
                else:
                    self.relay_once(resp, turn)
        except (BrokenPipeError, ConnectionResetError):
            log(f"{requested} -> {model}: client disconnected mid-response")
            return
        u = turn.usage or {}
        log(f"{requested} -> {model} {'stream' if stream else 'once'} finish={turn.finish} "
            f"tools={len(turn.calls)} in={u.get('prompt_tokens')} out={u.get('completion_tokens')} "
            f"{time.time() - started:.1f}s")

    def relay_stream(self, resp, turn: Turn) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        events = gemini_events(resp, turn)
        while True:
            try:
                event = next(events)
            except StopIteration:
                return
            except (UpstreamFailed, OSError, http.client.HTTPException) as e:
                log(f"stream failed, sent as error (no tool calls): {e}")
                self.sse({"error": {"code": 503, "message": f"gemini_bridge: {e}", "status": "UNAVAILABLE"}})
                return
            self.sse(event)  # a client-side write error propagates to do_POST

    def relay_once(self, resp, turn: Turn) -> None:
        try:
            data = json.load(resp)
            choice = (data.get("choices") or [{}])[0]
            turn.usage = data.get("usage")
            turn.finish = choice.get("finish_reason")
            parts = turn.feed(choice.get("message") or {}) + turn.call_parts()
        except (UpstreamFailed, ValueError, OSError, http.client.HTTPException) as e:
            log(f"response failed, sent as error: {e}")
            return self.fail(503, f"gemini_bridge: {e}")
        self.send_json(200, turn.response(parts or [{"text": ""}], final=True))

    def authorized(self, url) -> bool:
        given = self.headers.get("x-goog-api-key") or parse_qs(url.query).get("key", [""])[0]
        auth = self.headers.get("Authorization") or ""
        if not given and auth.startswith("Bearer "):
            given = auth[len("Bearer "):]
        return hmac.compare_digest(given.encode(), CFG["BRIDGE_KEY"].encode())

    def sse(self, obj: dict) -> None:
        self.wfile.write(b"data: " + json.dumps(obj).encode() + b"\r\n\r\n")
        self.wfile.flush()

    def send_json(self, code: int, obj: dict) -> None:
        out = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def fail(self, code: int, message: str) -> None:
        status = STATUS.get(code, "INTERNAL" if code >= 500 else "INVALID_ARGUMENT")
        self.send_json(code, {"error": {"code": code, "message": message, "status": status}})


def pipe(a: socket.socket, b: socket.socket) -> None:
    peer = {a: b, b: a}
    try:
        while True:
            readable, _, _ = select.select([a, b], [], [])
            for sock in readable:
                data = sock.recv(65536)
                if not data:
                    return
                peer[sock].sendall(data)
    except OSError:
        return


def exit_with_parent(parent: int) -> None:
    # Backstop for the wrapper's EXIT trap (which can't run on SIGKILL).
    while os.getppid() == parent:
        time.sleep(2)
    log("parent exited; shutting down")
    os._exit(0)


def main() -> None:
    required = ("BRIDGE_KEY", "UPSTREAM_URL", "UPSTREAM_KEY", "BRIDGE_MODEL", "BRIDGE_SMALL_MODEL")
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        sys.exit(f"gemini_bridge: missing env: {', '.join(missing)}")
    CFG.update({k: os.environ[k] for k in required})
    CFG["UPSTREAM_URL"] = CFG["UPSTREAM_URL"].rstrip("/")
    # Ctrl-C belongs to agy, which shares our process group. The wrapper stops
    # us with SIGTERM when agy exits.
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    CATALOG.update(load_catalog())

    server = ThreadingHTTPServer(("127.0.0.1", int(os.environ.get("BRIDGE_PORT") or 0)), Handler)
    server.daemon_threads = True
    port = server.server_address[1]
    port_file = os.environ.get("BRIDGE_PORT_FILE")
    if port_file:
        with open(port_file + ".tmp", "w") as f:
            f.write(f"{port}\n")
        os.replace(port_file + ".tmp", port_file)
    log(f"listening on 127.0.0.1:{port}; model={CFG['BRIDGE_MODEL']} small={CFG['BRIDGE_SMALL_MODEL']} "
        f"upstream={CFG['UPSTREAM_URL']} catalog={len(CATALOG)} models")
    threading.Thread(target=exit_with_parent, args=(os.getppid(),), daemon=True).start()
    server.serve_forever()


if __name__ == "__main__":
    main()
