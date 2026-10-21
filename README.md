# OpenCode Provider Setup Scripts

© 2026 CL-Andro / Mohammad Zaid (@cl-andro/mohammadzaid) — All Rights Reserved.

> ## ⚠️ WARNING — All code belongs to CL-Andro / Mohammad Zaid
>
> All source code, shell scripts, configuration templates, documentation, and
> associated materials in this repository are the exclusive intellectual
> property of **CL-Andro / Mohammad Zaid**. Unauthorized copying, modification,
> redistribution, publishing, or commercial use — in whole or in part — without
> prior written consent is strictly prohibited.

---

One-command setup scripts that connect **cloud LLM provider API keys** to
[OpenCode](https://opencode.ai). Each script is fully self-contained: it detects
your environment, checks dependencies, optionally installs OpenCode, writes the
provider config, stores the API key, exports the environment variables, and
verifies the connection.

Where a provider offers free-tier or trial models, those are included so you can
confirm the key works and test the integration. The same scripts work with paid
and production keys.

Works on **Termux**, **PRoot Distro (Debian 13/12, Ubuntu)**, and **native
Linux**.

## Quick start

```bash
git clone git@github-third:cl-andro/shell-script.git
cd shell-script

chmod +x ./*.sh
./inception-setup.sh            # prompts for the API key
```

`inception-setup.sh` also accepts the key up front to skip the prompt:

```bash
./inception-setup.sh sk_xxxxxxxxxxxxxxxx
# or
INCEPTION_API_KEY=sk_xxxxxxxxxxxxxxxx ./inception-setup.sh
```

Most scripts detect an existing `<PROVIDER>_API_KEY` in your environment and
offer to reuse it; otherwise they prompt for the key. Cloudflare and NVIDIA ask
for their credentials interactively.

## Scripts

| Script | Provider ID | Endpoint | Key variable(s) | Models |
| --- | --- | --- | --- | --- |
| [`cf-worker-setup.sh`](cf-worker-setup.sh) | `cloudflare-workers-ai` | Cloudflare Workers AI | `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_KEY` | OpenCode catalog + default picker (5) |
| [`gemini-setup.sh`](gemini-setup.sh) | `google` | Google AI Studio | `GEMINI_API_KEY`, `GOOGLE_API_KEY` | models.dev catalog |
| [`hcnsec-setup.sh`](hcnsec-setup.sh) | `hcnsec` | `https://api.hcnsec.cn/v1` | `HCN_API_KEY` | 12 |
| [`inception-setup.sh`](inception-setup.sh) | `inception` | `https://api.inceptionlabs.ai/v1` | `INCEPTION_API_KEY` | 3 |
| [`nex-setup.sh`](nex-setup.sh) | `nex` | `https://api.apinex.bond/v1` | `NEX_API_KEY` | 16 |
| [`nvidia-setup.sh`](nvidia-setup.sh) | `nvidia`, `nvidia-build` | `https://integrate.api.nvidia.com/v1` | `NVIDIA_API_KEY` | live-tested curated NIM list |
| [`radox-setup.sh`](radox-setup.sh) | `RadoxAI` | `https://radoxai.com/v1` | `RADOX_API_KEY` | 1 |
| [`token-harbor-setup.sh`](token-harbor-setup.sh) | `tokenharbor` | `https://tokenharbor.ai/v1` | `TOKENHARBOR_API_KEY` | 3 |
| [`xkiro-setup.sh`](xkiro-setup.sh) | `xkiro` | `https://api.xkiro.com/v1` | `XKIRO_API_KEY` | 36 |

### What each provider is for

- **Cloudflare Workers AI** — Workers AI models using Cloudflare's daily neuron
  allowance. Asks for your Account ID and API token, verifies the token, and
  lets you pick the default model.
- **Google AI Studio (Gemini)** — Gemini models through OpenCode's
  native `google` provider. Sets `google/gemini-2.5-flash` as the default.
- **HCNsec** — 12 Chinese/frontier models behind one API key,
  including DeepSeek V4.1 Flash, GLM 5.3 Flash, MiniMax M3, and Step 3.7 Flash.
- **Inception Labs** — Mercury diffusion models: `mercury-3` (1M context),
  `mercury-2.5`, and `mercury-2`, with `instant`/`low`/`medium`/`high`
  reasoning effort.
- **NEX (api.apinex.bond)** — 16 models, including Claude Sonnet
  4.6, Claude Opus 4.6, Kimi K3, Gemini 3.8 Flash, and DeepSeek V4 Pro.
- **NVIDIA Build (NIM)** — fetches the live catalog, health-tests a curated list
  of NIM endpoints, and only registers models that answer. Also configures the
  native `nvidia` provider and compaction defaults.
- **Radox AI** — one model, `claude-opus-4.8`, through
  `https://radoxai.com/v1` using a `cc_`-prefixed API key.
- **TokenHarbor** — 3 models: DeepSeek V4.1 Flash, Mimo V2.6 Flash, and
  Qwen 3.8 Flash.
- **XKiro** — 36 models across GLM, MiniMax, Mistral, and Qwen; several are
  free-tier endpoints useful for testing.

## What every script does

1. **Detects the environment** — Termux, PRoot, Debian 13/12, or generic Linux.
2. **Checks dependencies** — `python3` and `curl`; installs them with `apt-get`
   or `pkg` when missing.
3. **Checks OpenCode** — offers to install it with
   `curl -fsSL https://opencode.ai/install | bash` if it is not on `PATH`.
4. **Collects the API key** — reuses an existing environment variable or prompts
   for one; `inception-setup.sh` also accepts it as an argument.
5. **Writes the provider config** to `opencode.jsonc` (or `opencode.json`).
6. **Saves credentials** to `auth.json`.
7. **Injects models** into the `models.json` cache (provider-specific scripts).
8. **Exports environment variables** into `.bashrc`, `.profile`, and `.zshrc`.
9. **Validates connectivity** where supported — Cloudflare token check, NVIDIA
   model health tests, or an Inception `/v1/models` check.

The scripts also detect other reachable home directories — PRoot Debian/Ubuntu
rootfs and Termux `$HOME` — so the same run can configure OpenCode for all of
them.

## Files touched

| Path | Purpose |
| --- | --- |
| `~/.config/opencode/opencode.jsonc` | Provider, models, default model |
| `~/.config/opencode/opencode.json` | Used instead when it already exists |
| `~/.local/share/opencode/auth.json` | API key (`{"type": "api", "key": ...}`) |
| `~/.cache/opencode/models.json` | Fallback model catalog |
| `~/.bashrc`, `~/.profile`, `~/.zshrc` | `export <PROVIDER>_API_KEY="..."` |

> The scripts only modify OpenCode configuration in your home directory. They do
> not touch this repository.

## Example: generated provider config

`inception-setup.sh` produces this shape:

```json
{
  "provider": {
    "inception": {
      "name": "Inception Labs",
      "npm": "@ai-sdk/openai-compatible",
      "env": ["INCEPTION_API_KEY"],
      "options": {
        "baseURL": "https://api.inceptionlabs.ai/v1",
        "apiKey": "sk_..."
      },
      "models": {
        "mercury-3": {
          "name": "Mercury 3",
          "reasoning": true,
          "reasoning_options": [
            { "type": "effort", "values": ["instant", "low", "medium", "high"] }
          ],
          "tool_call": true,
          "limit": { "context": 1000000, "output": 131072 },
          "options": { "reasoningEffort": "low" }
        }
      }
    }
  }
}
```

## Model catalogs

<details>
<summary><strong>Inception Labs — 3 models</strong></summary>

| Model | Context | Max output | Input / output (per 1M) | Default reasoning |
| --- | --- | --- | --- | --- |
| `mercury-3` | 1,000,000 | 131,072 | $0.10 / $0.35 | `low` |
| `mercury-2.5` | 260,000 | 65,536 | $0.20 / $0.75 | `medium` |
| `mercury-2` | 128,000 | 50,000 | $0.25 / $0.75 | `medium` |

All three support tool calling, structured outputs, and `instant`, `low`,
`medium`, `high` reasoning effort.

</details>

<details>
<summary><strong>HCNsec — 12 models</strong></summary>

`hcnsec/deepseek-v4.1-flash`, `hcnsec/glm-4.5-air`, `hcnsec/qwen3.8-27b`,
`hcnsec/qwen3.8-flash-next`, `hcnsec/deepseek-v4-flash`,
`hcnsec/deepseek-v4-pro`, `hcnsec/spark-x2.5`, `hcnsec/glm-5.3-flash`,
`hcnsec/minimax-m3`, `hcnsec/step-3.7-flash`, `hcnsec/step-router-v1`,
`hcnsec/deepseek-v4-flash-vision-exp`

</details>

<details>
<summary><strong>NEX — 16 models</strong></summary>

`free/minimax-m3`, `free/gpt-6-luna`, `free/glm-5.3-flash`,
`free/deepseek-v4.1-flash`, `free/deepseek-v4-pro-0813`,
`free/mimo-v2.6-pro`, `free/mimo-v2.6-flash`, `free/claude-sonnet-4.6`,
`free/hy4`, `free/kimi-k3`, `free/claude-opus-4.6`, `free/gemini-3.8-flash`,
`free/muse-spark-1.3`, `free/gemini-3.1-pro`, `free/deepseek-v4-flash-0731`,
`free/qwen-3.8-max`

</details>

<details>
<summary><strong>Radox AI — 1 model</strong></summary>

`claude-opus-4.8`

</details>

<details>
<summary><strong>TokenHarbor — 3 models</strong></summary>

`deepseek-v4.1-flash:free`, `mimo-v2.6-flash:free`, `qwen3.8-flash:free`

</details>

<details>
<summary><strong>XKiro — 36 models</strong></summary>

- **GLM:** `z-ai/glm-5.3`
- **MiniMax:** `m3`, `m2.7`, `m2.7-highspeed`, `m2.5`, `m2.5-highspeed`, `m2.1`,
  `m2.1-highspeed`, `m2` (all `:free`)
- **Mistral:** `mistral-large-2512`, `mistral-medium-3.5`,
  `mistral-small-2603`, `codestral-2508`, `devstral-medium`, `ministral-14b`,
  `ministral-8b`, `ministral-3b`
- **Qwen:** `qwen3.8-omni-flash`, `qwen3.8-max`, `qwen3.7-max`,
  `qwen3.7-plus`, `qwen3.7-flash`, `qwen3.6-plus`, `qwen3.6-max-preview`,
  `qwen3.6-27b`, `qwen3.5-plus`, `qwen3.5-omni-plus`, `qwen3.6-35b-a3b`,
  `qwen3.5-flash`, `qwen3.5-397b-a17b`, `qwen3.5-omni-flash`, `qwen3-max`,
  `qwen-plus-2025-07-28`, `qwen3-coder-plus`, `qwen3-vl-plus`,
  `qwen3-omni-flash` (mostly `:free`)

</details>

<details>
<summary><strong>NVIDIA Build — live-tested models</strong></summary>

The script health-tests these candidates and registers only the ones that
respond:

`poolside/laguna-xs-2.1`, `nvidia/nemotron-3-ultra-550b-a55b`,
`nvidia/nemotron-3-nano-omni-30b-a3b-reasoning`,
`nvidia/nemotron-3-super-120b-a12b`,
`nvidia/nemotron-3.5-lightning-30b-a3b`,
`deepseek-ai/deepseek-v4-flash-0731`,
`meta/llama-3.2-11b-vision-instruct`, `openai/gpt-oss-20b`

</details>

<details>
<summary><strong>Google AI Studio — popular models</strong></summary>

`google/gemini-2.5-flash` (default), `google/gemini-2.5-pro`,
`google/gemini-2.5-flash-lite`, `google/gemini-3.8-flash`,
`google/gemini-3.7-flash`, `google/gemini-flash-latest`

The full list comes from OpenCode's built-in models.dev catalog.

</details>

<details>
<summary><strong>Cloudflare Workers AI — default picker</strong></summary>

`@cf/meta/llama-3.3-70b-instruct-fp8-fast` (default),
`@cf/deepseek-ai/deepseek-r1-distill-qwen-32b`,
`@cf/qwen/qwen2.5-coder-32b-instruct`,
`@cf/meta/llama-3.1-8b-instruct-fp8`,
`@cf/deepseek-ai/deepseek-v4-flash-0731`

The full Workers AI catalog comes from OpenCode's built-in model list.

</details>

## Requirements

- Linux, Termux, or a PRoot Distro (Debian 13/12, Ubuntu).
- `bash`, `curl`, and `python3` (the scripts install `curl`/`python3` when a
  package manager is available).
- `opencode` on `PATH` — or let the script install it.
- An API key / account for the provider you are configuring.

## After setup

```bash
opencode
```

Then:

1. Run `/models`.
2. Search for the provider (`inception`, `xkiro`, `nex`, …) or the model name.
3. Select the model and start chatting.

You can also preselect one from the CLI:

```bash
opencode -m inception/mercury-3
```

## Security notes

- **API keys are stored in plain text** in `auth.json`,
  `opencode.jsonc`/`opencode.json`, and your shell rc files. Protect those files
  and never commit them.
- The scripts read keys from your environment; they do not send them anywhere
  except the provider's own API endpoint.
- Provider endpoints are third-party services. Review their terms and privacy
  policies before sending code or data.
- Quotas, model availability, and pricing can change at any time.
- Review any script before running it, especially when it was downloaded from
  the internet.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Models do not appear | Restart OpenCode and run `/models`; keep `OPENCODE_DISABLE_MODELS_FETCH=1` set |
| `401` / unauthorized | Re-run the script with a valid key |
| `opencode: command not found` | Install it: `curl -fsSL https://opencode.ai/install \| bash` |
| Config not picked up in PRoot | Log into the distro and run the script there, or use the rootfs path it detects |
| Wrong home directory configured | Check `~/.config/opencode/` for the current user; the script prints every home it writes to |
| Model missing | The provider may have rotated or retired it — update the model list in the script |

## Repository layout

```text
.
├── cf-worker-setup.sh        # Cloudflare Workers AI
├── gemini-setup.sh           # Google AI Studio (Gemini)
├── hcnsec-setup.sh           # HCNsec
├── inception-setup.sh        # Inception Labs (Mercury)
├── nex-setup.sh              # NEX (api.apinex.bond)
├── nvidia-setup.sh           # NVIDIA Build / NIM
├── token-harbor-setup.sh     # TokenHarbor
├── xkiro-setup.sh            # XKiro
└── README.md
```

---

© 2026 CL-Andro / Mohammad Zaid (@cl-andro/mohammadzaid) — All Rights Reserved.

All source code, shell scripts, configuration templates, documentation, and
associated materials in this repository are the exclusive intellectual property
of CL-Andro / Mohammad Zaid. Unauthorized copying, modification, redistribution,
publishing, or commercial use — in whole or in part — without prior written
consent is strictly prohibited.
