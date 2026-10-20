#!/bin/bash
# Inception Labs (Mercury) Setup Script for Opencode
# Fully automatic setup - works on Termux, Proot, Debian 13/12
# Creates/fixes models.json and configures the Mercury chat models
#
# API reference (OpenAI-compatible):
#   POST https://api.inceptionlabs.ai/v1/chat/completions
#   Authorization: Bearer $INCEPTION_API_KEY
#
#   curl https://api.inceptionlabs.ai/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -H "Authorization: Bearer $INCEPTION_API_KEY" \
#     -d '{
#       "model": "mercury-3",
#       "reasoning_effort": "low",
#       "messages": [
#         {"role": "user", "content": "What is a diffusion model?"}
#       ]
#     }'

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

# Verify that the API key works (non-fatal, just a warning)
verify_api_key() {
    local api_key="$1"
    log_info "Checking Inception API key against https://api.inceptionlabs.ai/v1/models ..."

    local http_code
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" -m 20 \
        "https://api.inceptionlabs.ai/v1/models" \
        -H "Authorization: Bearer ${api_key}" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
        log_info "API key verified successfully"
    elif [ "$http_code" = "000" ]; then
        log_warn "Could not reach api.inceptionlabs.ai (network issue) - continuing anyway"
    else
        log_warn "API returned HTTP ${http_code} - the key may be invalid, continuing anyway"
    fi
}

# Fully standalone: setup inception in opencode.jsonc, auth.json, models.json and shell rc
setup_inception_models() {
    local api_key="$1"
    log_info "Configuring Inception Labs provider, models, and credentials..."

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
    export INCEPTION_API_KEY="$api_key"

    python3 << 'PYEOFSCRIPT'
import json
import os

USER_HOME = os.environ.get('USER_HOME', os.path.expanduser('~'))
API_KEY = os.environ.get('INCEPTION_API_KEY', '')

# Inception Labs chat models (OpenAI-compatible endpoint)
# Docs: https://docs.inceptionlabs.ai/get-started/models
mercury_models = {
    "mercury-3": {
        "id": "mercury-3",
        "name": "Mercury 3",
        "description": "Inception Mercury 3 diffusion model - 1M context, fast reasoning and tool calling",
        "family": "mercury",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "effort", "values": ["instant", "low", "medium", "high"]}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2025-04-01",
        "last_updated": "2025-04-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 1000000, "output": 131072},
        "cost": {"input": 0.10, "output": 0.35, "cache_read": 0.01},
        # Mercury 3 defaults to "low" when reasoning_effort is omitted
        "options": {"reasoningEffort": "low"}
    },
    "mercury-2.5": {
        "id": "mercury-2.5",
        "name": "Mercury 2.5",
        "description": "Inception Mercury 2.5 diffusion model - 260K context, reasoning and tool calling",
        "family": "mercury",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "effort", "values": ["instant", "low", "medium", "high"]}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2025-04-01",
        "last_updated": "2025-04-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 260000, "output": 65536},
        "cost": {"input": 0.20, "output": 0.75, "cache_read": 0.02},
        # Mercury 2.5 defaults to "medium" when reasoning_effort is omitted
        "options": {"reasoningEffort": "medium"}
    },
    "mercury-2": {
        "id": "mercury-2",
        "name": "Mercury 2",
        "description": "Inception Mercury 2 diffusion model - 128K context, fast chat and tool calling",
        "family": "mercury",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "effort", "values": ["instant", "low", "medium", "high"]}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2025-04-01",
        "last_updated": "2025-04-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 128000, "output": 50000},
        "cost": {"input": 0.25, "output": 0.75, "cache_read": 0.025},
        # Mercury 2 defaults to "medium" when reasoning_effort is omitted
        "options": {"reasoningEffort": "medium"}
    }
}

# 1. Update ~/.config/opencode/opencode.jsonc (and opencode.json)
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

config_data['provider']['inception'] = {
    "name": "Inception Labs",
    "npm": "@ai-sdk/openai-compatible",
    "env": ["INCEPTION_API_KEY"],
    "options": {
        "baseURL": "https://api.inceptionlabs.ai/v1",
        "apiKey": API_KEY
    },
    "models": mercury_models
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

auth_data['inception'] = {
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

if 'inception' not in data or not isinstance(data['inception'], dict):
    data['inception'] = {
        'id': 'inception',
        'env': ['INCEPTION_API_KEY'],
        'npm': '@ai-sdk/openai-compatible',
        'api': 'https://api.inceptionlabs.ai/v1',
        'name': 'Inception Labs',
        'doc': 'https://docs.inceptionlabs.ai',
        'models': {}
    }

if 'models' not in data['inception'] or not isinstance(data['inception']['models'], dict):
    data['inception']['models'] = {}

for model_key, model_config in mercury_models.items():
    data['inception']['models'][model_key] = model_config

with open(models_json, 'w') as f:
    json.dump(data, f, indent=2)
print(f"  -> Injected {len(mercury_models)} models into {models_json}")

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
    if 'export INCEPTION_API_KEY=' not in content:
        entries.append(f'export INCEPTION_API_KEY="{API_KEY}"')
    if 'export OPENCODE_DISABLE_MODELS_FETCH=' not in content:
        entries.append('export OPENCODE_DISABLE_MODELS_FETCH=1')

    if entries:
        try:
            with open(rc_path, 'a') as f:
                f.write('\n# Added by Inception Labs Opencode Setup\n' + '\n'.join(entries) + '\n')
            print(f"  -> Added environment exports to {rc_path}")
        except Exception:
            pass
PYEOFSCRIPT

    log_info "Setup finished for $user_home"
}

# Ask for Inception Labs API key
# Priority: first argument -> existing INCEPTION_API_KEY -> interactive prompt
ask_api_key() {
    local provided_key="$1"

    if [ -n "$provided_key" ]; then
        API_KEY="$provided_key"
    fi

    if [ -z "$API_KEY" ] && [ -n "$INCEPTION_API_KEY" ]; then
        read -p "Found existing INCEPTION_API_KEY. Use this key? (y/n) [y]: " use_existing
        if [[ "$use_existing" =~ ^[Yy]$ || -z "$use_existing" ]]; then
            API_KEY="$INCEPTION_API_KEY"
        fi
    fi

    if [ -z "$API_KEY" ]; then
        log_info "Please enter your Inception Labs API key"
        log_info "Get one at: https://platform.inceptionlabs.ai"
        read -p "INCEPTION_API_KEY: " API_KEY
    fi

    # Trim whitespace
    API_KEY=$(echo "$API_KEY" | xargs)

    if [ -z "$API_KEY" ]; then
        log_error "API key cannot be empty"
        exit 1
    fi

    if [[ ! "$API_KEY" =~ ^sk_ ]]; then
        log_warn "Inception keys usually start with 'sk_' - continuing anyway"
    fi

    # Export in current subshell session
    export INCEPTION_API_KEY="$API_KEY"
    export OPENCODE_DISABLE_MODELS_FETCH=1

    log_info "Inception Labs API key received"
}

# Main script execution
main() {
    log_info "========================================"
    log_info "Inception Labs Opencode Setup Script"
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
    ask_api_key "$1"
    log_info ""

    # Verify the key (non-fatal)
    verify_api_key "$API_KEY"
    log_info ""

    # Setup Inception models, config, auth, and shell profiles
    setup_inception_models "$API_KEY"

    log_info ""
    log_info "========================================"
    log_info "Setup Complete! ✅"
    log_info "========================================"
    log_info ""
    log_info "Your Inception Labs API is now configured with 3 Mercury chat models:"
    log_info ""

    # List available inception models
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
            models = list(d.get('provider', {}).get('inception', {}).get('models', {}).keys())
            if not models and 'inception' in d:
                models = list(d['inception'].get('models', {}).keys())
            if models:
                for i, m in enumerate(models, 1):
                    print(f'  {i}. {m}')
                break
        except Exception:
            pass
" | head -n 20

    log_info ""
    log_info "⚠️  To use in OpenCode:"
    log_info "  1. If you run in proot-distro, log in:"
    log_info "     proot-distro login debian"
    log_info "  2. Start OpenCode:"
    log_info "     opencode"
    log_info "  3. Type /models and search 'inception' or 'mercury'!"
    log_info ""
    log_info "Quick API test:"
    log_info "  curl https://api.inceptionlabs.ai/v1/chat/completions \\"
    log_info "    -H \"Content-Type: application/json\" \\"
    log_info "    -H \"Authorization: Bearer \$INCEPTION_API_KEY\" \\"
    log_info "    -d '{\"model\":\"mercury-3\",\"reasoning_effort\":\"low\",\"messages\":[{\"role\":\"user\",\"content\":\"What is a diffusion model?\"}]}'"
    log_info ""
    log_info "Happy coding! 🚀"
}

# Run main function
main "$1"
