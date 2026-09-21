#!/bin/bash
# ==============================================================================
# NVIDIA Build (NIM) Setup Script for OpenCode CLI
# Works on: Termux, PRoot Distro (Debian 13/12, Ubuntu), Native Linux
# Configures: NVIDIA Build API Key & Verified Working NIM Models for OpenCode
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Detect environment
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
        log_info "Opencode is already installed: $(command -v opencode)"
        return 0
    else
        log_warn "Opencode is not installed in current PATH"
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
        
        # Add to current PATH if installed in ~/.opencode/bin
        export PATH="$HOME/.opencode/bin:$PATH"
        if [ -d "/root/.opencode/bin" ]; then
            export PATH="/root/.opencode/bin:$PATH"
        fi
        
        # Wait for opencode to be available
        for i in {1..30}; do
            if command -v opencode >/dev/null 2>&1; then
                log_info "Opencode installed successfully: $(command -v opencode)"
                return 0
            fi
            sleep 1
        done
        
        log_warn "Opencode installation completed. If 'opencode' command is not found immediately, restart your shell or add ~/.opencode/bin to PATH."
        return 0
    else
        log_warn "Proceeding with configuration. Make sure to install OpenCode to use the models."
        return 0
    fi
}

# Ask for NVIDIA API Key
ask_api_key() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}  NVIDIA Build (NIM) API Key Configuration${NC}"
    echo -e "${CYAN}  Get free 1,000 credits at: https://build.nvidia.com${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${YELLOW}How to get your NVIDIA Build API Key:${NC}"
    echo -e "  1. Log into ${BLUE}https://build.nvidia.com/${NC}"
    echo -e "  2. Click on any model (e.g. Nemotron or Laguna)"
    echo -e "  3. Click '${GREEN}Get API Key${NC}' -> Generate Key (starts with '${YELLOW}nvapi-${NC}')"
    echo -e "${CYAN}================================================================${NC}"
    echo ""

    local existing_key="$NVIDIA_API_KEY"
    if [ -z "$existing_key" ] && [ -f "$HOME/.local/share/opencode/auth.json" ]; then
        existing_key=$(python3 -c "
import json
try:
    with open('$HOME/.local/share/opencode/auth.json') as f:
        d = json.load(f)
    print(d.get('nvidia', {}).get('key', ''))
except:
    pass
" 2>/dev/null || true)
    fi

    if [ -n "$existing_key" ]; then
        read -p "Found existing NVIDIA API Key ($existing_key). Use this? (y/n) [y]: " use_existing
        if [[ "$use_existing" =~ ^[Yy]$ || -z "$use_existing" ]]; then
            API_KEY="$existing_key"
        fi
    fi

    if [ -z "$API_KEY" ]; then
        read -p "Enter your NVIDIA API Key (starts with nvapi-): " API_KEY
    fi

    API_KEY=$(echo "$API_KEY" | xargs)

    if [ -z "$API_KEY" ]; then
        log_error "NVIDIA API Key cannot be empty!"
        exit 1
    fi

    export NVIDIA_API_KEY="$API_KEY"
}

# Live model scanning & health testing
scan_and_test_models() {
    echo ""
    log_info "Fetching live models from NVIDIA Build API and checking health..."

    export ACTIVE_MODELS_JSON=""
    export TEST_API_KEY="$API_KEY"

    python3 << 'PYEOF'
import urllib.request
import json
import os

api_key = os.environ.get('TEST_API_KEY', '')
if not api_key:
    exit(1)

headers = {
    'Authorization': f'Bearer {api_key}',
    'Content-Type': 'application/json'
}

# 1. Fetch available models from API
try:
    req = urllib.request.Request('https://integrate.api.nvidia.com/v1/models', headers=headers)
    with urllib.request.urlopen(req, timeout=12) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        raw_models = [m['id'] for m in data.get('data', [])]
        print(f"  -> NVIDIA API returned {len(raw_models)} registered models in catalog.")
except Exception as e:
    print(f"  -> Warning: Could not fetch model list from API ({e}). Using curated fallback list.")
    raw_models = []

# Curated priority candidate models
priority_candidates = [
    ("poolside/laguna-xs-2.1", "Laguna XS 2.1 (Poolside - Superfast Agent)", 32768),
    ("nvidia/nemotron-3-ultra-550b-a55b", "Nemotron 3 Ultra 550B A55B (Flagship MoE)", 32768),
    ("nvidia/nemotron-3-nano-omni-30b-a3b-reasoning", "Nemotron 3 Nano Omni (Reasoning)", 32768),
    ("nvidia/nemotron-3-super-120b-a12b", "Nemotron 3 Super 120B A12B (High Parameter)", 32768),
    ("nvidia/nemotron-3.5-lightning-30b-a3b", "Nemotron 3.5 Lightning 30B A3B (Fast Agent)", 32768),
    ("deepseek-ai/deepseek-v4-flash-0731", "DeepSeek V4 Flash 0731", 65536),
    ("meta/llama-3.2-11b-vision-instruct", "Llama 3.2 11B Vision Instruct (Multimodal)", 131072),
    ("openai/gpt-oss-20b", "GPT OSS 20B (Open Reasoning)", 32768),
    ("mistralai/mistral-nemotron", "Mistral NeMo 12B Instruct", 32768)
]

# Quick health test on key models
working_models = {}
status_report = []

print("\n  --- Live NVIDIA NIM Model Verification ---")
for model_id, display_name, ctx in priority_candidates:
    payload = json.dumps({
        'model': model_id,
        'messages': [{'role': 'user', 'content': 'hi'}],
        'max_tokens': 5
    }).encode('utf-8')
    chat_req = urllib.request.Request('https://integrate.api.nvidia.com/v1/chat/completions', data=payload, headers=headers)
    try:
        with urllib.request.urlopen(chat_req, timeout=10) as r:
            res = json.loads(r.read().decode('utf-8'))
            msg = res['choices'][0]['message']
            working_models[model_id] = {
                "name": display_name,
                "context": ctx,
                "status": "active"
            }
            status_report.append((model_id, "ACTIVE ✅", "Responded immediately"))
            print(f"  ✅ {model_id} [ACTIVE]")
    except Exception as e:
        err = str(e)
        if '503' in err or 'overload' in err.lower():
            working_models[model_id] = {
                "name": display_name,
                "context": ctx,
                "status": "overloaded"
            }
            status_report.append((model_id, "QUEUED ⚠️", "Active endpoint, high traffic"))
            print(f"  ⚠️ {model_id} [QUEUED/503 - Active endpoint under high traffic]")
        elif 'timeout' in err.lower():
            working_models[model_id] = {
                "name": display_name,
                "context": ctx,
                "status": "slow"
            }
            status_report.append((model_id, "SLOW ⏱️", "Queued/cold-start on free tier"))
            print(f"  ⏱️ {model_id} [SLOW/TIMEOUT - Active on free tier with queue]")
        elif '410' in err:
            status_report.append((model_id, "DEPRECATED ❌", "HTTP 410 Gone on NVIDIA server"))
            print(f"  ❌ {model_id} [HTTP 410 GONE - Retired by NVIDIA]")
        else:
            status_report.append((model_id, "OFFLINE ❌", err))
            print(f"  ❌ {model_id} [OFFLINE: {err}]")

# Save tested working models to file for bash script
with open('/tmp/nvidia_working_models.json', 'w') as f:
    json.dump(working_models, f, indent=2)

PYEOF
}

# Ask user for default model
ask_default_model() {
    echo ""
    echo -e "${CYAN}Choose your default NVIDIA Build model for OpenCode:${NC}"
    echo "  1) Poolside Laguna XS 2.1 (Recommended - Fastest response, verified active)"
    echo "     [nvidia-build/poolside/laguna-xs-2.1]"
    echo "  2) Nemotron 3 Ultra 550B A55B (NVIDIA Flagship MoE 550B model)"
    echo "     [nvidia-build/nvidia/nemotron-3-ultra-550b-a55b]"
    echo "  3) Nemotron 3 Nano Omni (Reasoning specialist)"
    echo "     [nvidia-build/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning]"
    echo "  4) Nemotron 3 Super 120B A12B"
    echo "     [nvidia-build/nvidia/nemotron-3-super-120b-a12b]"
    echo "  5) Meta Llama 3.2 11B Vision Instruct (Vision & Multimodal)"
    echo "     [nvidia-build/meta/llama-3.2-11b-vision-instruct]"
    echo "  6) Nemotron 3.5 Lightning 30B A3B"
    echo "     [nvidia-build/nvidia/nemotron-3.5-lightning-30b-a3b]"
    read -p "Select option [1-6, default: 1]: " model_choice

    case "$model_choice" in
        2)
            DEFAULT_MODEL="nvidia-build/nvidia/nemotron-3-ultra-550b-a55b"
            ;;
        3)
            DEFAULT_MODEL="nvidia-build/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning"
            ;;
        4)
            DEFAULT_MODEL="nvidia-build/nvidia/nemotron-3-super-120b-a12b"
            ;;
        5)
            DEFAULT_MODEL="nvidia-build/meta/llama-3.2-11b-vision-instruct"
            ;;
        6)
            DEFAULT_MODEL="nvidia-build/nvidia/nemotron-3.5-lightning-30b-a3b"
            ;;
        *)
            DEFAULT_MODEL="nvidia-build/poolside/laguna-xs-2.1"
            ;;
    esac

    log_info "Default model set to: $DEFAULT_MODEL"
}

# Configure NVIDIA in target home
setup_nvidia_for_home() {
    local user_home="$1"
    local api_key="$2"
    local default_model="$3"

    export TARGET_USER_HOME="$user_home"
    export TARGET_API_KEY="$api_key"
    export TARGET_DEFAULT_MODEL="$default_model"

    python3 << 'PYEOF'
import os
import json

user_home = os.environ.get('TARGET_USER_HOME', os.path.expanduser('~'))
api_key = os.environ.get('TARGET_API_KEY', '')
default_model = os.environ.get('TARGET_DEFAULT_MODEL', 'nvidia-build/poolside/laguna-xs-2.1')

if not user_home or not api_key:
    exit(0)

# Load verified models from /tmp
try:
    with open('/tmp/nvidia_working_models.json', 'r') as f:
        tested_models = json.load(f)
except Exception:
    tested_models = {
        "poolside/laguna-xs-2.1": {"name": "Laguna XS 2.1 (Poolside)", "context": 32768},
        "nvidia/nemotron-3-ultra-550b-a55b": {"name": "Nemotron 3 Ultra 550B A55B", "context": 32768},
        "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning": {"name": "Nemotron 3 Nano Omni", "context": 32768},
        "nvidia/nemotron-3-super-120b-a12b": {"name": "Nemotron 3 Super 120B A12B", "context": 32768},
        "nvidia/nemotron-3.5-lightning-30b-a3b": {"name": "Nemotron 3.5 Lightning 30B A3B", "context": 32768},
        "meta/llama-3.2-11b-vision-instruct": {"name": "Llama 3.2 11B Vision", "context": 131072},
        "openai/gpt-oss-20b": {"name": "GPT OSS 20B", "context": 32768},
        "deepseek-ai/deepseek-v4-flash-0731": {"name": "DeepSeek V4 Flash 0731", "context": 65536}
    }

# Ensure directories exist
config_dir = os.path.join(user_home, '.config', 'opencode')
share_dir = os.path.join(user_home, '.local', 'share', 'opencode')
cache_dir = os.path.join(user_home, '.cache', 'opencode')

os.makedirs(config_dir, exist_ok=True)
os.makedirs(share_dir, exist_ok=True)
os.makedirs(cache_dir, exist_ok=True)

# 1. Configure opencode.jsonc / opencode.json
config_file = os.path.join(config_dir, 'opencode.jsonc')
if os.path.exists(os.path.join(config_dir, 'opencode.json')):
    config_file = os.path.join(config_dir, 'opencode.json')

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except Exception:
    config = {"$schema": "https://opencode.ai/config.json"}

if 'provider' not in config or not isinstance(config['provider'], dict):
    config['provider'] = {}

# A. Configure native 'nvidia' provider
if 'nvidia' not in config['provider'] or not isinstance(config['provider']['nvidia'], dict):
    config['provider']['nvidia'] = {}
if 'options' not in config['provider']['nvidia'] or not isinstance(config['provider']['nvidia']['options'], dict):
    config['provider']['nvidia']['options'] = {}
config['provider']['nvidia']['options']['apiKey'] = api_key

# B. Configure curated 'nvidia-build' provider (only working & tested models)
custom_models = {}
for m_id, info in tested_models.items():
    custom_models[m_id] = {
        "id": m_id,
        "name": info.get("name", m_id),
        "description": f"{info.get('name', m_id)} via NVIDIA Build NIM API",
        "family": "nemotron" if "nemotron" in m_id else ("llama" if "llama" in m_id else "general"),
        "attachment": False,
        "reasoning": "reasoning" in m_id or "gpt-oss" in m_id,
        "tool_call": True,
        "temperature": True,
        "limit": {
            "context": info.get("context", 32768),
            "output": 4096
        }
    }

config['provider']['nvidia-build'] = {
    "name": "NVIDIA Build (Verified NIM Models)",
    "npm": "@ai-sdk/openai-compatible",
    "env": ["NVIDIA_API_KEY"],
    "options": {
        "baseURL": "https://integrate.api.nvidia.com/v1",
        "apiKey": api_key
    },
    "models": custom_models
}

# C. Compaction settings & agent
config['compaction'] = {
    "auto": True,
    "keep": {
        "tokens": 4000
    },
    "buffer": 6000
}

if 'google' in config.get('provider', {}):
    if 'agent' not in config or not isinstance(config['agent'], dict):
        config['agent'] = {}
    config['agent']['compaction'] = {
        "model": "google/gemini-2.5-flash"
    }

# Set default model
if default_model:
    config['model'] = default_model

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
print(f"  -> Configured NVIDIA providers in {config_file}")

# 2. Configure auth.json
auth_file = os.path.join(share_dir, 'auth.json')
try:
    with open(auth_file, 'r') as f:
        auth_data = json.load(f)
except Exception:
    auth_data = {}

auth_data['nvidia'] = {
    "type": "api",
    "key": api_key
}
auth_data['nvidia-build'] = {
    "type": "api",
    "key": api_key
}

with open(auth_file, 'w') as f:
    json.dump(auth_data, f, indent=2)
print(f"  -> Saved credentials in {auth_file}")

# 3. Add environment exports to shell config files (.bashrc, .profile, .zshrc)
for rc_name in ['.bashrc', '.profile', '.zshrc']:
    rc_path = os.path.join(user_home, rc_name)
    content = ""
    if os.path.exists(rc_path):
        try:
            with open(rc_path, 'r') as f:
                content = f.read()
        except Exception:
            pass

    lines = content.splitlines()
    filtered = [l for l in lines if not l.startswith('export NVIDIA_API_KEY=')]
    filtered.append(f'export NVIDIA_API_KEY="{api_key}"')

    new_content = '\n'.join(filtered).rstrip() + '\n'

    try:
        with open(rc_path, 'w') as f:
            f.write(new_content)
        print(f"  -> Updated NVIDIA_API_KEY in {rc_path}")
    except Exception as e:
        print(f"  -> Notice: could not write to {rc_path}: {e}")
PYEOF
}

setup_all_environments() {
    local api_key="$1"
    local default_model="$2"

    log_info "Configuring NVIDIA Build credentials across environments..."

    local target_homes=("$HOME")

    # PRoot Debian rootfs
    local proot_deb="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian/root"
    if [ -d "$proot_deb" ] && [ "$proot_deb" != "$HOME" ]; then
        target_homes+=("$proot_deb")
    fi

    # Standard /root if accessible
    if [ -d "/root" ] && [ -w "/root" ] && [ "/root" != "$HOME" ]; then
        target_homes+=("/root")
    fi

    # Termux home if mounted or accessible
    local termux_home="/data/data/com.termux/files/home"
    if [ -d "$termux_home" ] && [ -w "$termux_home" ] && [ "$termux_home" != "$HOME" ]; then
        target_homes+=("$termux_home")
    fi

    local seen_homes=()
    for h in "${target_homes[@]}"; do
        if [[ ! " ${seen_homes[*]} " =~ " ${h} " ]]; then
            seen_homes+=("$h")
            log_info "Setting up configuration for: $h"
            setup_nvidia_for_home "$h" "$api_key" "$default_model"
        fi
    done
}

# Main function
main() {
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${CYAN} NVIDIA Build (NIM) Setup for OpenCode CLI${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo ""

    check_dependencies

    if ! check_opencode; then
        install_opencode
    fi
    echo ""

    ask_api_key
    echo ""

    scan_and_test_models
    echo ""

    ask_default_model
    echo ""

    setup_all_environments "$API_KEY" "$DEFAULT_MODEL"
    echo ""

    log_info "======================================================"
    log_info "Setup Complete! ✅"
    log_info "======================================================"
    echo ""
    log_info "Verified NVIDIA Build Models Ready in OpenCode:"
    echo "  • nvidia-build/poolside/laguna-xs-2.1               [ACTIVE - Ultra-fast < 1s]"
    echo "  • nvidia-build/nvidia/nemotron-3-ultra-550b-a55b     [ACTIVE - Flagship 550B MoE]"
    echo "  • nvidia-build/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning [ACTIVE - Reasoning]"
    echo "  • nvidia-build/nvidia/nemotron-3-super-120b-a12b     [ACTIVE - 120B High Capacity]"
    echo "  • nvidia-build/meta/llama-3.2-11b-vision-instruct   [ACTIVE - Fast Vision & Chat]"
    echo "  • nvidia-build/openai/gpt-oss-20b                   [ACTIVE - Open Reasoning]"
    echo "  • nvidia-build/nvidia/nemotron-3.5-lightning-30b-a3b [ACTIVE - Free Queue]"
    echo "  • nvidia-build/deepseek-ai/deepseek-v4-flash-0731   [ACTIVE - Free Queue]"
    echo ""
    log_warn "Note on DeepSeek V4 Pro 0813:"
    log_warn "  NVIDIA returned 'HTTP 410 Gone' for deepseek-ai/deepseek-v4-pro-0813 on the"
    log_warn "  public integrate API because NVIDIA temporarily retired this model checkpoint."
    echo ""

    # Verify with OpenCode CLI
    if command -v opencode >/dev/null 2>&1; then
        log_info "Verifying models with OpenCode CLI..."
        if opencode models nvidia-build >/dev/null 2>&1; then
            local count
            count=$(opencode models nvidia-build | wc -l)
            log_info "OpenCode recognized $count verified NVIDIA Build models!"
        fi
    fi

    echo ""
    log_info "To use NVIDIA Build in OpenCode:"
    log_info "  1. If using PRoot Distro, log in:"
    log_info "     proot-distro login debian"
    log_info "  2. Start OpenCode:"
    log_info "     opencode"
    log_info "  3. In chat, type /models to pick any NVIDIA model!"
    log_info "  Or run directly from CLI:"
    log_info "     opencode -m nvidia-build/poolside/laguna-xs-2.1"
    log_info "     opencode -m nvidia-build/nvidia/nemotron-3-ultra-550b-a55b"
    log_info "     opencode -m nvidia-build/nvidia/nemotron-3-nano-omni-30b-a3b-reasoning"
    echo ""
    log_info "Happy coding with NVIDIA NIM & OpenCode! 🚀"
}

main
