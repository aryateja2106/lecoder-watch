# 0002 — edge0: OpenAI-style function calling on `/v1/chat/completions`

Against `Edge0-AI/Edge0` main as of 2026-09-20 (clone under `references/external/repos/edge0`,
gitignored). Upstream drops the request's `tools` array and never parses the model's
`<tool_call>` blocks, so any agent loop that speaks OpenAI tool calls gets prose instead of a call.

The patch (3 files, ~40 lines):
- `server/chat.py`: hand `payload["tools"]` to the chat template (both the engine's
  `encode_chat` path and the tokenizer `apply_chat_template` fallback).
- `engine/ling.py`: `encode_chat(..., tools=None)` renders them (the vendored Ling/Qwen
  template already knows `<tools>`).
- `server/app.py`: `_extract_tool_calls` turns `<tool_call>name<arg_key>k</arg_key><arg_value>v
  </arg_value></tool_call>` into `tool_calls` entries and sets `finish_reason: tool_calls`.

Measured on this Mac (M-series, 24 GB), edge0-8b (Ling 3.0 based, 4-bit, prerouter K=8):
`get_time({"machine":"jetson"})` in 3.8 s, 14 completion tokens; plain chat ~11 tok/s warm;
RSS 3.8–4.1 GB with the model mmapped. Apply with
`git -C references/external/repos/edge0 apply ../../../patches/0002-edge0-openai-tool-calls.patch`.
Worth an upstream PR; the streaming (`_chat_stream`) path is not patched.
