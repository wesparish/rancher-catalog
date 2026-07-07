# Claude Code & OpenCode → local vLLM

Copy the shell blocks into your terminal. **Do not** `source` this file as one script if you paste multiple sections together.

---

## Claude Code

Paste into your terminal (same host as vLLM; Anthropic-compatible URL **without** `/v1`):

```bash
export ANTHROPIC_BASE_URL="http://w-dock4.weshouse:30800"
export ANTHROPIC_API_KEY="sk-local-key"
export ANTHROPIC_AUTH_TOKEN="dummy-token"
export ANTHROPIC_DEFAULT_SONNET_MODEL="Qwen3.5-9B-AWQ"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="Qwen3.5-9B-AWQ"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=32768

claude
```

If inference feels ~90% slower, per-request hashes may be breaking vLLM prefix caching; often addressed in vLLM **> 0.17.1**.

### Gemma 4 26B (port 30801)

```bash
export ANTHROPIC_BASE_URL="http://w-dock4.weshouse:30801"
export ANTHROPIC_API_KEY="sk-local-key"
export ANTHROPIC_AUTH_TOKEN="dummy-token"
export ANTHROPIC_DEFAULT_SONNET_MODEL="gemma-4-26b"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="gemma-4-26b"
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=4096

claude
```

32768 token context window, prefix caching enabled. Image+audio inputs supported (audio encoder disabled by default — remove `--limit-mm-per-prompt` from the Helm values to enable).

> **Warning:** Claude Code's system prompt + tool definitions consume ~28K tokens before any conversation, leaving very little room within the 32K context window. Expect frequent `VLLMValidationError: maximum context length exceeded` errors as history accumulates. Use OpenCode instead for a much lighter prompt footprint.

---

## OpenCode — Gemma 4 26B (port 30801)

OpenCode sends a significantly smaller system prompt than Claude Code, making it a better fit for gemma-4-26b's 32K context window.

Set in `~/.config/opencode/opencode.json` as shown in the OpenCode section below — the `vllm-gemma` provider points to port 30801.

---

## OpenCode

[OpenCode](https://opencode.ai/) uses the **OpenAI-compatible** vLLM surface: `baseURL` must end with **`/v1`** (unlike Claude Code's `ANTHROPIC_BASE_URL`).

### Install

```bash
curl -fsSL https://opencode.ai/install | bash
```

On macOS with Homebrew: `brew install opencode`

### `~/.config/opencode/opencode.json`

Merge into that file (or create it), or copy [`opencode.json`](opencode.json) from this folder. Model id must match vLLM `--served-model-name` (or the exact `id` from `GET …/v1/models`). Set `"model"` / `"small_model"` to `vllm-local/Qwen3.5-9B-AWQ` when that container is running (same port **8000** as Qwen2.5—only one at a time). For the **64k** vLLM variant, raise `limit.context` to **65536** for that model entry.

**Important:** `provider.models.*.limit` is **OpenCode metadata** only (UI "context left", compaction hints). It does **not** change vLLM's hard cap. The server enforces `--max-model-len` only. If chat + tools exceed that, vLLM returns **400**. Fix: raise vLLM `--max-model-len` (VRAM permitting), start a fresh session, and/or tune compaction — see [OpenCode config](https://opencode.ai/docs/config/). Keep `limit.context` aligned with your vLLM `--max-model-len`.

Qwen3.5-9B-AWQ (port 30800) and gemma-4-26b (port 30801) are on **different ports**, so they need separate provider entries.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "vllm-gemma/gemma-4-26b",
  "small_model": "vllm-gemma/gemma-4-26b",
  "compaction": {
    "auto": true,
    "prune": true,
    "reserved": 2048
  },
  "provider": {
    "vllm-qwen": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "vLLM Qwen (port 30800)",
      "options": {
        "baseURL": "http://w-dock4.weshouse:30800/v1",
        "apiKey": "sk-local-key"
      },
      "models": {
        "Qwen3.5-9B-AWQ": {
          "name": "Qwen3.5-9B-AWQ (vLLM)",
          "limit": {
            "context": 32768,
            "output": 8192
          }
        }
      }
    },
    "vllm-gemma": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "vLLM Gemma (port 30801)",
      "options": {
        "baseURL": "http://w-dock4.weshouse:30801/v1",
        "apiKey": "sk-local-key"
      },
      "models": {
        "gemma-4-26b": {
          "name": "Gemma 4 26B (vLLM)",
          "limit": {
            "context": 32768,
            "output": 8192
          }
        }
      }
    }
  }
}
```

### Run

```bash
opencode
```

In the TUI: `/models`. Docs: [config](https://opencode.ai/docs/config/) · [custom provider](https://opencode.ai/docs/providers#custom-provider)
