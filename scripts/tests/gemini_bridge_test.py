#!/usr/bin/env python3
"""Offline checks for scripts/gemini_bridge.py, on request shapes captured from agy 1.5.14.

Run from the repo root:  python3 -I scripts/tests/gemini_bridge_test.py
Prints GEMINI_BRIDGE_OK; any failure raises. No network, no agy, no proxy.
"""
import base64
import importlib.util
import json
import os

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "gemini_bridge.py")
spec = importlib.util.spec_from_file_location("gemini_bridge", path)
gb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gb)
gb.CFG.update(BRIDGE_MODEL="main-model", BRIDGE_SMALL_MODEL="small-model")
gb.CATALOG.update({"main-model": {"max_output": 64000, "efforts": ["low", "medium", "high"]}})

sig = base64.b64encode(b"opaque-123").decode()
agy_request = {
    "systemInstruction": {"parts": [{"text": "sys A"}, {"text": "sys B"}]},
    "contents": [
        {"role": "user", "parts": [{"text": "read two files"}]},
        {"role": "model", "parts": [
            {"text": "pondering", "thought": True},
            {"functionCall": {"id": "call_1", "name": "read_file", "args": {"Path": "a"}}, "thoughtSignature": sig},
            {"functionCall": {"id": "call_2", "name": "read_file", "args": {"Path": "b"}}},
        ]},
        # agy sends tool results under role "model" (LiteLLM upstream drops them there).
        {"role": "model", "parts": [
            {"functionResponse": {"id": "call_1", "name": "read_file", "response": {"output": "A"}}},
            {"functionResponse": {"id": "call_2", "name": "read_file", "response": {"output": "B"}}},
        ]},
    ],
    "tools": [{"functionDeclarations": [{"name": "read_file", "description": "d",
                                         "parametersJsonSchema": {"type": "object"}}]}],
    "generationConfig": {"maxOutputTokens": 65535, "thinkingConfig": {"includeThoughts": True, "thinkingBudget": 1024}},
}
req = gb.to_openai(agy_request, gb.pick_model("gemini-3.1-pro-preview"))
msgs = req["messages"]
assert req["model"] == "main-model"
assert msgs[0] == {"role": "system", "content": "sys A\n\nsys B"}
assert msgs[1] == {"role": "user", "content": "read two files"}
assert msgs[2]["role"] == "assistant" and msgs[2]["content"] is None, "thought text must not leak into history"
assert [c["id"] for c in msgs[2]["tool_calls"]] == ["call_1", "call_2"], "ids must round-trip, not call_<name>"
assert msgs[2]["reasoning_opaque"] == "opaque-123"
assert msgs[3:] == [{"role": "tool", "tool_call_id": "call_1", "content": "A"},
                    {"role": "tool", "tool_call_id": "call_2", "content": "B"}], msgs[3:]
assert req["tools"][0]["function"]["parameters"] == {"type": "object"}
assert req["max_tokens"] == 64000 and req["reasoning_effort"] == "low"
assert gb.pick_model("gemini-3.1-flash-lite-preview") == "small-model"

# Calls without ids (other Gemini clients) get unique ids, matched to results by name in order.
anon = gb.to_openai({"contents": [
    {"role": "model", "parts": [{"functionCall": {"name": "f", "args": {}}}, {"functionCall": {"name": "f", "args": {}}}]},
    {"role": "user", "parts": [{"functionResponse": {"name": "f", "response": {"x": 1}}},
                               {"functionResponse": {"name": "f", "response": {"x": 2}}}]},
]}, "main-model")["messages"]
call_ids = [c["id"] for c in anon[0]["tool_calls"]]
assert len(set(call_ids)) == 2 and [m["tool_call_id"] for m in anon[1:]] == call_ids

# Copilot stream -> Gemini: thoughts and text stream through; calls arrive once, at the end.
turn = gb.Turn(include_thoughts=True)
assert turn.feed({"reasoning_text": "hmm"}) == [{"text": "hmm", "thought": True}]
assert turn.feed({"content": "ok"}) == [{"text": "ok"}]
turn.feed({"tool_calls": [{"index": 0, "id": "call_9", "function": {"name": "run_command", "arguments": '{"Comm'}}],
           "reasoning_opaque": "op"})
turn.feed({"tool_calls": [{"index": 0, "function": {"arguments": 'andLine": "ls"}'}}]})
turn.finish, turn.usage = "tool_calls", {"prompt_tokens": 10, "completion_tokens": 7, "reasoning_tokens": 5}
final = turn.response(turn.call_parts(), final=True)
part = final["candidates"][0]["content"]["parts"][0]
assert part["functionCall"] == {"name": "run_command", "args": {"CommandLine": "ls"}, "id": "call_9"}
assert base64.b64decode(part["thoughtSignature"]).decode() == "op"
assert final["candidates"][0]["finishReason"] == "STOP"
assert final["usageMetadata"] == {"promptTokenCount": 10, "candidatesTokenCount": 2,
                                  "totalTokenCount": 17, "thoughtsTokenCount": 5}, json.dumps(final)

# A cut-off turn must never reach agy as a tool call (it would be executed).
def sse(*chunks):
    return [b"data: " + json.dumps(c).encode() + b"\n" for c in chunks]


call_chunk = {"choices": [{"delta": {"tool_calls": [
    {"index": 0, "id": "c1", "function": {"name": "run_command", "arguments": '{"CommandLine": "ls"}'}}]}}]}
done_chunk = {"choices": [{"delta": {}, "finish_reason": "tool_calls"}]}
for label, lines in (
    ("error after a complete call", sse(call_chunk, {"error": {"message": "boom"}})),
    ("error after finish_reason", sse(call_chunk, done_chunk, {"error": {"message": "boom"}})),
    ("EOF before finish_reason", sse(call_chunk)),
    ("unparseable arguments", sse({"choices": [{"delta": {"tool_calls": [
        {"index": 0, "id": "c1", "function": {"name": "run_command", "arguments": '{"Comm'}}]}}]}, done_chunk)),
):
    emitted = []
    try:
        for event in gb.gemini_events(lines, gb.Turn(include_thoughts=False)):
            emitted.append(event)
    except gb.UpstreamFailed:
        pass
    else:
        raise AssertionError(f"{label}: stream should fail")
    assert "functionCall" not in json.dumps(emitted), f"{label}: tool call leaked: {emitted}"
ok_events = list(gb.gemini_events(sse(call_chunk, done_chunk) + [b"data: [DONE]\n"], gb.Turn(include_thoughts=False)))
assert ok_events[-1]["candidates"][0]["content"]["parts"][0]["functionCall"]["name"] == "run_command"

# An image from the first of two parallel tool results waits until both results are in.
image = {"inlineData": {"mimeType": "image/png", "data": "AAAA"}}
split = gb.to_openai({"contents": [
    {"role": "model", "parts": [{"functionCall": {"id": "a", "name": "read_file", "args": {}}},
                                {"functionCall": {"id": "b", "name": "read_file", "args": {}}}]},
    {"role": "model", "parts": [{"functionResponse": {"id": "a", "name": "read_file", "response": {"output": "img"},
                                                      "parts": [image]}}]},
    {"role": "model", "parts": [{"functionResponse": {"id": "b", "name": "read_file", "response": {"output": "txt"}}}]},
]}, "main-model")["messages"]
assert [m["role"] for m in split] == ["assistant", "tool", "tool", "user"], [m["role"] for m in split]

print("GEMINI_BRIDGE_OK")
