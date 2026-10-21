#!/bin/bash
# Radox AI Setup Script for Opencode
# Fully automatic setup - works on Termux, Proot, Debian 13/12
# Creates/fixes models.json and configures the full Radox AI model catalog

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect operating system/environment
detect_env() {
    if [ -n "$PREFIX" ] || command -v proot >/dev/null 2>&1; then
        echo "termux/proot"
    elif [ -f /etc/debian_version ] || [ -d /etc/debian ]; then
        if [ -f /etc/debian_version ]; then
            DEBIAN_VERSION=$(cat /etc/debian_version | cut -d. -f1)
            echo "debian-${DEBIAN_VERSION}"
        else
            echo "debian"
        fi
    elif [ -n "$XDG_DATA_HOME" ] || [ -d "$HOME/.local/share" ]; then
        echo "generic-linux"
    else
        echo "unknown"
    fi
}

ENV_TYPE=$(detect_env)
log_info "Detected environment: $ENV_TYPE"

# Detect proot-distro environment
IS_PROOT_DISTRO=0
if [ -d "/data/data/com.termux" ] || [ -n "$PROOT_DISTRO" ] || grep -q "proot" /proc/1/cgroup 2>/dev/null; then
    IS_PROOT_DISTRO=1
fi

# In proot-distro, default login is root and opencode installs to /root/.opencode/
# Just set up for the current user (root in proot-distro)
if [ "$IS_PROOT_DISTRO" = "1" ]; then
    log_info "Detected proot-distro environment"
    if [ "$(id -u)" = "0" ]; then
        log_info "Running as root - setting up models for root user (/root/.cache/opencode/)"
    else
        log_info "Running as user - setting up models for $HOME"
    fi
fi

# Ensure essential dependencies are available (python3 and curl)
check_dependencies() {
    local missing=()
    if ! command -v python3 >/dev/null 2>&1; then
        missing+=("python3")
    fi
    if ! command -v curl >/dev/null 2>&1; then
        missing+=("curl")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Missing required packages: ${missing[*]}"
        if command -v apt-get >/dev/null 2>&1; then
            log_info "Attempting to install ${missing[*]} via apt-get..."
            apt-get update && apt-get install -y "${missing[@]}"
        elif command -v pkg >/dev/null 2>&1; then
            log_info "Attempting to install ${missing[*]} via pkg..."
            pkg install -y "${missing[@]}"
        else
            log_error "Please install ${missing[*]} manually and run the script again."
            exit 1
        fi
    fi
}

# Check if opencode is installed
check_opencode() {
    if command -v opencode >/dev/null 2>&1; then
        log_info "Opencode is already installed"
        return 0
    else
        log_info "Opencode is not installed"
        return 1
    fi
}

# Install opencode with user permission
install_opencode() {
    log_info "Attempting to install opencode..."
    log_info "Download command: curl -fsSL https://opencode.ai/install | bash"
    
    read -p "Do you want to install opencode now? (y/n): " install_choice
    
    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        log_info "Installing opencode..."
        curl -fsSL https://opencode.ai/install | bash
        
        # Wait for opencode to be available
        for i in {1..30}; do
            if command -v opencode >/dev/null 2>&1; then
                log_info "Opencode installed successfully!"
                return 0
            fi
            sleep 1
        done
        
        log_error "Opencode installation timed out"
        return 1
    else
        log_error "Opencode installation cancelled. Script requires opencode to function."
        exit 1
    fi
}

# Fully standalone: setup RadoxAI in opencode.jsonc, auth.json, models.json and shell rc
setup_radox_models() {
    local api_key="$1"
    log_info "Configuring Radox AI provider, models, and credentials..."
    
    # Collect all relevant home directories (Termux host, proot-distro debian root, etc.)
    local target_homes=("$HOME")
    
    # Proot debian rootfs when run from Termux native
    local proot_deb="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian/root"
    if [ -d "$proot_deb" ] && [ "$proot_deb" != "$HOME" ]; then
        target_homes+=("$proot_deb")
    fi
    
    # Proot ubuntu rootfs when run from Termux native
    local proot_ubu="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root"
    if [ -d "$proot_ubu" ] && [ "$proot_ubu" != "$HOME" ]; then
        target_homes+=("$proot_ubu")
    fi
    
    # Standard /root if running with root permissions or accessible
    if [ -d "/root" ] && [ -w "/root" ] && [ "/root" != "$HOME" ]; then
        target_homes+=("/root")
    fi
    
    # Termux home if running inside proot but Termux home is mounted or accessible
    local termux_home="/data/data/com.termux/files/home"
    if [ -d "$termux_home" ] && [ -w "$termux_home" ] && [ "$termux_home" != "$HOME" ]; then
        target_homes+=("$termux_home")
    fi

    # Deduplicate and setup
    local seen_homes=()
    for h in "${target_homes[@]}"; do
        if [[ ! " ${seen_homes[*]} " =~ " ${h} " ]]; then
            seen_homes+=("$h")
            log_info "Setting up configuration for: $h"
            setup_models_for_user "$h" "$api_key"
        fi
    done
}

setup_models_for_user() {
    local user_home="$1"
    local api_key="$2"
    
    export USER_HOME="$user_home"
    export RADOX_API_KEY="$api_key"
    
    python3 << 'PYEOFSCRIPT'
import json
import os
import urllib.request

USER_HOME = os.environ.get('USER_HOME', os.path.expanduser('~'))
API_KEY = os.environ.get('RADOX_API_KEY', '')

# Radox AI catalog (33 models).
# Tuple layout: (display name, context window, input $/1M, output $/1M,
#                capabilities, description)
MODEL_SPECS = {
    "claude-fable-5": ("Claude Fable 5", 1000000, 16.606, 16.606, ["reasoning", "vision", "tools", "streaming", "json_mode"], "Anthropic premium model. Outstanding coding and reasoning with top Code Arena score."),
    "claude-fable-5.1": ("Claude Fable 5.1", 1000000, 16.606, 16.606, ["reasoning", "vision", "tools", "streaming", "json_mode"], "Anthropic premium model. Outstanding coding and reasoning with top Code Arena score."),
    "claude-mythos-preview": ("Claude Mythos Preview", 1000000, 8.303, 8.303, ["reasoning", "vision", "tools", "streaming", "json_mode"], "Anthropic next-gen preview model. Cutting-edge reasoning, not yet generally released."),
    "claude-opus-4.6": ("Claude Opus 4.6", 1000000, 8.303, 8.303, ["reasoning", "vision", "tools", "streaming", "json_mode"], "Anthropic Opus-class model. Reliable reasoning and agentic performance."),
    "claude-opus-4.7": ("Claude Opus 4.7", 1000000, 8.303, 8.303, ["reasoning", "vision", "tools", "streaming", "json_mode"], "Anthropic Opus-class model. Strong coding and reasoning, high Code Arena score."),
    "claude-opus-4.8": ("Claude Opus 4.8", 1000000, 8.303, 8.303, ["reasoning", "vision", "tools", "streaming", "json_mode"], "Anthropic Opus-class model. Reliable reasoning and coding performance."),
    "claude-opus-5": ("Claude Opus 5", 1000000, 8.303, 8.303, ["reasoning", "vision", "tools", "streaming", "json_mode"], "Anthropic's most capable model. Exceptional reasoning and agentic performance."),
    "claude-opus-5.5": ("Claude Opus 5.5", 1000000, 8.303, 8.303, ["reasoning", "vision", "tools", "streaming", "json_mode"], "Anthropic's most capable model. Exceptional reasoning and agentic performance."),
    "claude-sonnet-5": ("Claude Sonnet 5", 1000000, 3.3235, 3.3235, ["reasoning", "vision", "tools", "streaming", "json_mode"], "Anthropic balanced model. Great coding and reasoning at a lower cost."),
    "deepseek-v4-flash-0731": ("DeepSeek-V4-Flash-0731", 1048576, 0.115, 0.115, ["reasoning", "tools", "streaming", "json_mode"], "DeepSeek fast open model. Very affordable with solid reasoning, 304B params."),
    "deepseek-v4-pro-0813": ("DeepSeek-V4-Pro-0813", 1048576, 0.552, 0.552, ["reasoning", "tools", "streaming", "json_mode"], "DeepSeek open-source pro model. Excellent reasoning and coding, 1.6T params."),
    "deepseek-v4-pro-max": ("DeepSeek-V4-Pro-Max", 1048576, 2.047, 2.047, ["reasoning", "tools", "streaming", "json_mode"], "DeepSeek top open model. Maximum capability with 1.6T params."),
    "gemini-3.1-pro": ("Gemini 3.1 Pro", 1048576, 4.4735, 4.4735, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "Google pro model. Strong reasoning and coding with high Code Arena score."),
    "gemini-3.6-flash": ("Gemini 3.6 Flash", 1048576, 2.4955, 2.4955, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "Google fast model. Very quick responses with good reasoning, 364c/s."),
    "gemini-3.7-flash": ("Gemini 3.7 Flash", 1048576, 1.242, 1.242, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "Google latest Flash model. Very fast with strong reasoning, 479c/s."),
    "gemma-2-2b": ("Gemma 2 2B", 8192, 0.115, 0.23, ["streaming", "json_mode"], "Lightweight open model by Google. Fast and efficient for everyday tasks."),
    "glm-5.2": ("GLM-5.2", 1000000, 1.357, 1.357, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "Zhipu AI open model. Good reasoning and coding, 753B params."),
    "glm-5.3": ("GLM-5.3", 1000000, 1.357, 1.357, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "Zhipu AI latest model. Strong reasoning and agentic capability, 753B params."),
    "gpt-5.5": ("GPT-5.5", 1050000, 8.947, 8.947, ["reasoning", "vision", "tools", "streaming", "json_mode"], "OpenAI capable model. Solid reasoning and coding performance."),
    "gpt-5.5-pro": ("GPT-5.5 Pro", 1050000, 8.947, 8.947, ["reasoning", "vision", "tools", "streaming", "json_mode"], "OpenAI pro-tier model. Enhanced reasoning and coding over base 5.5."),
    "gpt-5.6-luna": ("GPT-5.6 Luna", 1050000, 0.3565, 0.3565, ["reasoning", "vision", "tools", "streaming", "json_mode"], "OpenAI efficient model. Great value with strong reasoning, 290c/s speed."),
    "gpt-5.6-sol": ("GPT-5.6 Sol", 1050000, 8.947, 8.947, ["reasoning", "vision", "tools", "streaming", "json_mode"], "OpenAI flagship model. Top-tier reasoning, coding, and agentic capability."),
    "gpt-5.6-terra": ("GPT-5.6 Terra", 1050000, 3.5765, 3.5765, ["reasoning", "vision", "tools", "streaming", "json_mode"], "OpenAI high-end model. Strong reasoning and coding at a mid price point."),
    "grok-4.5": ("Grok 4.5", 500000, 2.806, 2.806, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "xAI model. Strong reasoning and agentic capability."),
    "grok-4.6": ("Grok 4.6", 500000, 2.806, 2.806, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "xAI latest model. Improved reasoning and coding over 4.5."),
    "kimi-k2.6": ("Kimi K2.6", 1000000, 1.219, 1.219, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "Moonshot AI open model. Strong reasoning and coding, 1.0T params."),
    "kimi-k3": ("Kimi K3", 1000000, 4.9795, 4.9795, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "Moonshot AI open-source flagship. Strong reasoning and coding, 2.8T params."),
    "muse-spark-1.1": ("Muse Spark 1.1", 1000000, 1.817, 1.817, ["reasoning", "vision", "tools", "streaming", "json_mode"], "Meta Muse Spark series. Fast and capable with strong reasoning scores."),
    "qwen3.7-max": ("Qwen3.7 Max", 1000000, 1.7595, 1.7595, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "Alibaba Qwen pro model. Strong reasoning and coding performance."),
    "qwen3.8-27b": ("Qwen3.8-27B", 262144, 0.575, 0.575, ["reasoning", "tools", "streaming", "json_mode"], "Alibaba Qwen compact open model. Efficient 27.8B params with solid capability."),
    "qwen3.8-max": ("Qwen3.8 Max", 1000000, 1.7595, 1.7595, ["reasoning", "vision", "tools", "streaming", "json_mode", "web_search"], "Alibaba Qwen flagship open model. Strong all-round capability, 2.4T params."),
    "seed-2.1-pro": ("Seed 2.1 Pro", 262144, 1.15, 1.15, ["reasoning", "vision", "tools", "streaming", "json_mode"], "ByteDance Seed series pro model. Strong reasoning and coding."),
    "seed-2.1-turbo": ("Seed 2.1 Turbo", 262144, 0.92, 0.92, ["reasoning", "vision", "tools", "streaming", "json_mode"], "ByteDance Seed turbo model. Fast with solid reasoning and coding."),
}

FAMILY_PREFIXES = ("claude", "deepseek", "gemini", "gemma", "glm", "gpt",
                   "grok", "kimi", "muse", "qwen", "seed")


def family_of(model_id):
    for prefix in FAMILY_PREFIXES:
        if model_id.startswith(prefix):
            return prefix
    return model_id.split("-")[0]


def build_model(model_id, spec):
    name, context, cost_in, cost_out, caps, description = spec
    reasoning = "reasoning" in caps
    model = {
        "id": model_id,
        "name": name,
        "description": description,
        "family": family_of(model_id),
        "attachment": "vision" in caps,
        "reasoning": reasoning,
        "tool_call": "tools" in caps,
        "structured_output": "json_mode" in caps,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": context, "output": 8192},
        "cost": {"input": cost_in, "output": cost_out, "cache_read": 0}
    }
    if reasoning:
        model["reasoning_options"] = [{"type": "toggle"}]
    return model


def fetch_live_model_ids(api_key):
    """Ask /v1/models for the models this key can access."""
    if not api_key:
        return []
    request = urllib.request.Request(
        "https://radoxai.com/v1/models",
        headers={
            "Authorization": "Bearer " + api_key,
            "Accept": "application/json",
            "User-Agent": "curl/8.5.0",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.load(response)
        return [entry["id"] for entry in payload.get("data", []) if entry.get("id")]
    except Exception:
        return []


all_models = {model_id: build_model(model_id, spec)
              for model_id, spec in MODEL_SPECS.items()}

# Add any newly published models the key can see but the built-in list lacks
live_ids = fetch_live_model_ids(API_KEY)
added_live = []
for model_id in live_ids:
    if model_id in all_models:
        continue
    all_models[model_id] = {
        "id": model_id,
        "name": model_id,
        "description": "Radox AI model discovered via /v1/models",
        "family": family_of(model_id),
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [{"type": "toggle"}],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 128000, "output": 8192}
    }
    added_live.append(model_id)

if live_ids:
    print(f"  -> Live catalog: {len(live_ids)} models accessible with this key")
elif API_KEY:
    print("  -> Live catalog unavailable, using built-in 33-model list")
if added_live:
    print(f"  -> Added {len(added_live)} live-only model(s): {', '.join(sorted(added_live))}")

## 1. Update ~/.config/opencode/opencode.jsonc (and opencode.json)
config_dir = os.path.join(USER_HOME, '.config', 'opencode')
os.makedirs(config_dir, exist_ok=True)
config_path = os.path.join(config_dir, 'opencode.jsonc')
if os.path.exists(os.path.join(config_dir, 'opencode.json')):
    config_path = os.path.join(config_dir, 'opencode.json')

try:
    with open(config_path, 'r') as f:
        config_data = json.load(f)
except Exception:
    config_data = {"$schema": "https://opencode.ai/config.json"}

if 'provider' not in config_data or not isinstance(config_data['provider'], dict):
    config_data['provider'] = {}

config_data['provider']['RadoxAI'] = {
    "name": "Radox AI",
    "npm": "@ai-sdk/openai-compatible",
    "env": ["RADOX_API_KEY"],
    "options": {
        "baseURL": "https://radoxai.com/v1",
        "apiKey": API_KEY
    },
    "models": all_models
}

with open(config_path, 'w') as f:
    json.dump(config_data, f, indent=2)
print(f"  -> Configured provider in {config_path}")

# 2. Update ~/.local/share/opencode/auth.json
share_dir = os.path.join(USER_HOME, '.local', 'share', 'opencode')
os.makedirs(share_dir, exist_ok=True)
auth_path = os.path.join(share_dir, 'auth.json')
try:
    with open(auth_path, 'r') as f:
        auth_data = json.load(f)
except Exception:
    auth_data = {}

auth_data['RadoxAI'] = {
    "type": "api",
    "key": API_KEY
}

with open(auth_path, 'w') as f:
    json.dump(auth_data, f, indent=2)
print(f"  -> Saved credentials in {auth_path}")

# 3. Update ~/.cache/opencode/models.json (fallback cache)
cache_dir = os.path.join(USER_HOME, '.cache', 'opencode')
os.makedirs(cache_dir, exist_ok=True)
models_json = os.path.join(cache_dir, 'models.json')
try:
    with open(models_json, 'r') as f:
        data = json.load(f)
except Exception:
    data = {}

if 'RadoxAI' not in data or not isinstance(data['RadoxAI'], dict):
    data['RadoxAI'] = {
        'id': 'RadoxAI',
        'env': ['RADOX_API_KEY'],
        'npm': '@ai-sdk/openai-compatible',
        'api': 'https://radoxai.com/v1',
        'name': 'Radox AI',
        'doc': 'https://radoxai.com',
        'models': {}
    }

if 'models' not in data['RadoxAI'] or not isinstance(data['RadoxAI']['models'], dict):
    data['RadoxAI']['models'] = {}

for model_key, model_config in all_models.items():
    data['RadoxAI']['models'][model_key] = model_config

with open(models_json, 'w') as f:
    json.dump(data, f, indent=2)
print(f"  -> Injected {len(all_models)} models into {models_json}")

# 4. Automatically append to shell config files (.bashrc, .profile, .zshrc)
for rc in ['.bashrc', '.profile', '.zshrc']:
    rc_path = os.path.join(USER_HOME, rc)
    content = ""
    if os.path.exists(rc_path):
        try:
            with open(rc_path, 'r') as f:
                content = f.read()
        except Exception:
            pass
    
    entries = []
    if 'export RADOX_API_KEY=' not in content:
        entries.append(f'export RADOX_API_KEY="{API_KEY}"')
    if 'export OPENCODE_DISABLE_MODELS_FETCH=' not in content:
        entries.append('export OPENCODE_DISABLE_MODELS_FETCH=1')
    
    if entries:
        try:
            with open(rc_path, 'a') as f:
                f.write('\n# Added by Radox AI Opencode Setup\n' + '\n'.join(entries) + '\n')
            print(f"  -> Added environment exports to {rc_path}")
        except Exception:
            pass
PYEOFSCRIPT
    
    log_info "Setup finished for $user_home"
}

# Ask for Radox AI API key
ask_api_key() {
    log_info "Please enter your Radox AI API key (starts with cc_)"
    read -p "RADOX_API_KEY: " RADOX_API_KEY
    
    if [ -z "$RADOX_API_KEY" ]; then
        log_error "API key cannot be empty"
        exit 1
    fi
    
    # Export in current subshell session
    export RADOX_API_KEY="$RADOX_API_KEY"
    export OPENCODE_DISABLE_MODELS_FETCH=1
    
    log_info "Radox AI API key received"
}

# Main script execution
main() {
    log_info "========================================"
    log_info "Radox AI Opencode Setup Script"
    log_info "========================================"
    log_info ""
    
    # Check dependencies (python3 and curl)
    check_dependencies

    # Check if opencode is installed
    if ! check_opencode; then
        install_opencode
    fi
    
    log_info "Opencode is ready"
    log_info ""
    
    # Ask for API key first so it can be written to all configs
    ask_api_key
    log_info ""
    
    # Setup Radox AI models, config, auth, and shell profiles
    setup_radox_models "$RADOX_API_KEY"
    
    log_info ""
    log_info "========================================"
    log_info "Setup Complete! ✅"
    log_info "========================================"
    log_info ""
    log_info "Your Radox AI API is now configured with the full model catalog:"
    log_info ""
    
    # List available RadoxAI models
    python3 -c "
import json
import os
for path in [
    os.path.expanduser('~/.config/opencode/opencode.jsonc'),
    os.path.expanduser('~/.config/opencode/opencode.json'),
    '/root/.config/opencode/opencode.jsonc',
    os.path.expanduser('~/.cache/opencode/models.json')
]:
    if os.path.exists(path):
        try:
            with open(path) as f:
                d = json.load(f)
            models = list(d.get('provider', {}).get('RadoxAI', {}).get('models', {}).keys())
            if not models and 'RadoxAI' in d:
                models = list(d['RadoxAI'].get('models', {}).keys())
            if models:
                for i, m in enumerate(sorted(models), 1):
                    print(f'  {i}. {m}')
                break
        except Exception:
            pass
" | head -n 60
    
    log_info ""
    log_info "⚠️  To use in OpenCode:"
    log_info "  1. If you run in proot-distro, log in:"
    log_info "     proot-distro login debian"
    log_info "  2. Start OpenCode:"
    log_info "     opencode"
    log_info "  3. Type /models and search 'RadoxAI' to see all models!"
    log_info ""
    log_info "Happy coding! 🚀"
}

# Run main function
main