#!/bin/bash
# Radox AI Setup Script for Opencode
# Fully automatic setup - works on Termux, Proot, Debian 13/12
# Creates/fixes models.json and configures the Radox AI model

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

USER_HOME = os.environ.get('USER_HOME', os.path.expanduser('~'))
API_KEY = os.environ.get('RADOX_API_KEY', '')

# Free model definitions to add under RadoxAI
all_free_models = {
    "claude-opus-4.8": {
        "id": "claude-opus-4.8",
        "name": "claude-opus-4.8",
        "description": "Claude Opus 4.8 via Radox AI API",
        "family": "claude",
        "attachment": True,
        "reasoning": True,
        "reasoning_options": [{"type": "toggle"}],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 200000, "output": 64000},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    }
}

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
    "models": all_free_models
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

for model_key, model_config in all_free_models.items():
    data['RadoxAI']['models'][model_key] = model_config

with open(models_json, 'w') as f:
    json.dump(data, f, indent=2)
print(f"  -> Injected {len(all_free_models)} models into {models_json}")

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
    log_info "Your Radox AI API is now configured with the model:"
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
    log_info "  3. Type /models and search 'RadoxAI' to see the model!"
    log_info ""
    log_info "Happy coding! 🚀"
}

# Run main function
main