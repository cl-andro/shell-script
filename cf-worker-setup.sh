#!/bin/bash
# ==============================================================================
# Cloudflare Workers AI Setup Script for OpenCode CLI
# Works on: Termux, PRoot Distro (Debian 13/12, Ubuntu), Native Linux
# Configures: Cloudflare Workers AI Free Tier Models for OpenCode Agent
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

# Ask for Cloudflare Account ID and API Token
ask_credentials() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}  Cloudflare Workers AI Configuration${NC}"
    echo -e "${CYAN}  10,000 Neurons/day Free on Cloudflare for Everyone!${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${YELLOW}How to get your credentials in 2 minutes:${NC}"
    echo -e "  1. Log into ${BLUE}https://dash.cloudflare.com/${NC}"
    echo -e "  2. Go to ${YELLOW}Workers & Pages${NC} or ${YELLOW}Overview${NC} -> Copy ${GREEN}Account ID${NC} (right sidebar)"
    echo -e "  3. Go to ${BLUE}https://dash.cloudflare.com/profile/api-tokens${NC}"
    echo -e "     Click 'Create Token' -> Use template '${GREEN}Workers AI (Read)${NC}' -> Create & Copy Token"
    echo -e "${CYAN}================================================================${NC}"
    echo ""

    # 1. Ask for Cloudflare Account ID
    if [ -n "$CLOUDFLARE_ACCOUNT_ID" ] && [[ ! "$CLOUDFLARE_ACCOUNT_ID" =~ ^cfut_ ]]; then
        read -p "Found existing CLOUDFLARE_ACCOUNT_ID ($CLOUDFLARE_ACCOUNT_ID). Use this? (y/n) [y]: " use_existing_account
        if [[ "$use_existing_account" =~ ^[Yy]$ || -z "$use_existing_account" ]]; then
            ACCOUNT_ID="$CLOUDFLARE_ACCOUNT_ID"
        fi
    fi

    while true; do
        if [ -z "$ACCOUNT_ID" ]; then
            echo -e "${YELLOW}Step 1: Cloudflare Account ID${NC}"
            echo -e "  Copy your 32-character hex string from ${BLUE}https://dash.cloudflare.com/${NC}"
            echo -e "  (Visible in your browser address bar: dash.cloudflare.com/<ACCOUNT_ID> or right sidebar under 'Account ID')"
            read -p "Enter your Cloudflare Account ID: " ACCOUNT_ID
        fi

        ACCOUNT_ID=$(echo "$ACCOUNT_ID" | xargs)

        if [ -z "$ACCOUNT_ID" ]; then
            log_error "Cloudflare Account ID cannot be empty!"
            continue
        fi

        if [[ "$ACCOUNT_ID" =~ ^cfut_ ]]; then
            log_error "Error: You entered your API Token ('$ACCOUNT_ID') into the Account ID field!"
            echo -e "${YELLOW}Hint: The Account ID is a separate 32-character hex string (only 0-9 and a-f), NOT the token!${NC}"
            ACCOUNT_ID=""
            continue
        fi

        if [ ${#ACCOUNT_ID} -ne 32 ]; then
            log_warn "Notice: Account ID is usually exactly 32 hex characters (your input has ${#ACCOUNT_ID} characters)."
            read -p "Are you sure this is your Account ID? (y/n) [y]: " confirm_acc
            if [[ "$confirm_acc" =~ ^[Nn]$ ]]; then
                ACCOUNT_ID=""
                continue
            fi
        fi
        break
    done

    # 2. Ask for Cloudflare API Token (cfut_ prefix is Cloudflare's official User Token format)
    local existing_key="${CLOUDFLARE_API_KEY:-$CLOUDFLARE_API_TOKEN}"
    if [ -n "$existing_key" ] && [ "$existing_key" != "$ACCOUNT_ID" ]; then
        read -p "Found existing Cloudflare API Token. Use this? (y/n) [y]: " use_existing_key
        if [[ "$use_existing_key" =~ ^[Yy]$ || -z "$use_existing_key" ]]; then
            API_KEY="$existing_key"
        fi
    fi

    while true; do
        if [ -z "$API_KEY" ]; then
            echo ""
            echo -e "${YELLOW}Step 2: Cloudflare API Token${NC}"
            echo -e "  Get from ${BLUE}https://dash.cloudflare.com/profile/api-tokens${NC}"
            echo -e "  (Can start with 'cfut_' for User Tokens or standard format)"
            read -p "Enter your Cloudflare API Token: " API_KEY
        fi

        API_KEY=$(echo "$API_KEY" | xargs)

        if [ -z "$API_KEY" ]; then
            log_error "Cloudflare API Token cannot be empty!"
            continue
        fi

        if [ "$API_KEY" = "$ACCOUNT_ID" ]; then
            log_error "Error: API Token cannot be identical to Account ID!"
            API_KEY=""
            continue
        fi
        break
    done

    # Export for current session
    export CLOUDFLARE_ACCOUNT_ID="$ACCOUNT_ID"
    export CLOUDFLARE_API_KEY="$API_KEY"
    export CLOUDFLARE_API_TOKEN="$API_KEY"
}

# Ask user for preferred default model
ask_default_model() {
    echo ""
    echo -e "${CYAN}Choose your default Cloudflare Workers AI model for OpenCode:${NC}"
    echo "  1) Meta Llama 3.3 70B Instruct (Recommended - Best overall coding agent)"
    echo "     [cloudflare-workers-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast]"
    echo "  2) DeepSeek R1 Distill Qwen 32B (Best reasoning & math distillation)"
    echo "     [cloudflare-workers-ai/@cf/deepseek-ai/deepseek-r1-distill-qwen-32b]"
    echo "  3) Qwen 2.5 Coder 32B Instruct (Specialized code generation & refactoring)"
    echo "     [cloudflare-workers-ai/@cf/qwen/qwen2.5-coder-32b-instruct]"
    echo "  4) Meta Llama 3.1 8B Instruct (Ultra-fast, low neuron consumption)"
    echo "     [cloudflare-workers-ai/@cf/meta/llama-3.1-8b-instruct-fp8]"
    echo "  5) DeepSeek V4 Flash (High speed modern flash model)"
    echo "     [cloudflare-workers-ai/@cf/deepseek-ai/deepseek-v4-flash-0731]"
    echo "  6) Keep current default model unchanged"
    read -p "Select option [1-6, default: 1]: " model_choice

    case "$model_choice" in
        2)
            DEFAULT_MODEL="cloudflare-workers-ai/@cf/deepseek-ai/deepseek-r1-distill-qwen-32b"
            ;;
        3)
            DEFAULT_MODEL="cloudflare-workers-ai/@cf/qwen/qwen2.5-coder-32b-instruct"
            ;;
        4)
            DEFAULT_MODEL="cloudflare-workers-ai/@cf/meta/llama-3.1-8b-instruct-fp8"
            ;;
        5)
            DEFAULT_MODEL="cloudflare-workers-ai/@cf/deepseek-ai/deepseek-v4-flash-0731"
            ;;
        6)
            DEFAULT_MODEL=""
            ;;
        *)
            DEFAULT_MODEL="cloudflare-workers-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast"
            ;;
    esac

    if [ -n "$DEFAULT_MODEL" ]; then
        log_info "Default model set to: $DEFAULT_MODEL"
    else
        log_info "Keeping current default model setting"
    fi
}

# API connectivity test
test_connection() {
    log_info "Testing connection to Cloudflare..."
    
    # 1. First test token validity with Cloudflare's token verification endpoint
    local token_verify_json
    token_verify_json=$(curl -s --max-time 10 -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" 2>/dev/null || echo "{}")

    if echo "$token_verify_json" | grep -q '"status":"active"'; then
        log_info "API Token Status: VALID AND ACTIVE ✅"
    elif echo "$token_verify_json" | grep -q '"Authentication error"'; then
        log_warn "Cloudflare Token Verify returned: Invalid or Expired Token."
    fi

    # 2. Test chat completions with the Account ID
    log_info "Testing Workers AI chat endpoint for Account: ${ACCOUNT_ID}..."
    local test_url="https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/ai/v1/chat/completions"
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 -X POST "$test_url" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d '{"model":"@cf/meta/llama-3.2-1b-instruct","messages":[{"role":"user","content":"test"}],"max_tokens":1}' || echo "000")

    if [ "$http_code" = "200" ]; then
        log_info "Workers AI Endpoint Test: SUCCESSFUL (HTTP 200) ✅"
    elif [ "$http_code" = "401" ]; then
        log_warn "Cloudflare returned HTTP 401 (Authorization Failed)."
        log_warn "Possible causes:"
        log_warn "  1. The Account ID (${ACCOUNT_ID}) is incorrect or doesn't match this token."
        log_warn "     Check your 32-character hex Account ID at: https://dash.cloudflare.com/"
        log_warn "  2. The token permissions do not include 'Account > Workers AI > Read'."
        read -p "Do you still want to proceed with this configuration? (y/n) [y]: " cont_choice
        if [[ "$cont_choice" =~ ^[Nn]$ ]]; then
            log_error "Aborted by user."
            exit 1
        fi
    elif [ "$http_code" = "404" ] || [ "$http_code" = "400" ]; then
        log_warn "Cloudflare returned HTTP $http_code (Invalid Account ID or Path)."
        log_warn "Please check your Account ID: $ACCOUNT_ID"
        read -p "Do you still want to proceed with this configuration? (y/n) [y]: " cont_choice
        if [[ "$cont_choice" =~ ^[Nn]$ ]]; then
            log_error "Aborted by user."
            exit 1
        fi
    else
        log_warn "API test returned HTTP $http_code (network or rate-limit check)."
        log_warn "Proceeding with configuration..."
    fi
}

# Configure Cloudflare Workers AI for a target user home directory
setup_cf_for_home() {
    local user_home="$1"
    local account_id="$2"
    local api_key="$3"
    local default_model="$4"

    export TARGET_USER_HOME="$user_home"
    export TARGET_ACCOUNT_ID="$account_id"
    export TARGET_API_KEY="$api_key"
    export TARGET_DEFAULT_MODEL="$default_model"

    python3 << 'PYEOF'
import os
import json

user_home = os.environ.get('TARGET_USER_HOME', os.path.expanduser('~'))
account_id = os.environ.get('TARGET_ACCOUNT_ID', '')
api_key = os.environ.get('TARGET_API_KEY', '')
default_model = os.environ.get('TARGET_DEFAULT_MODEL', '')

if not user_home or not account_id or not api_key:
    exit(0)

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

# Configure cloudflare-workers-ai provider options
if 'cloudflare-workers-ai' not in config['provider'] or not isinstance(config['provider']['cloudflare-workers-ai'], dict):
    config['provider']['cloudflare-workers-ai'] = {}

if 'options' not in config['provider']['cloudflare-workers-ai'] or not isinstance(config['provider']['cloudflare-workers-ai']['options'], dict):
    config['provider']['cloudflare-workers-ai']['options'] = {}

config['provider']['cloudflare-workers-ai']['options']['apiKey'] = api_key

# Set realistic context limits for Cloudflare Workers AI models
# (Cloudflare enforces 8k-80k tokens depending on the model, rather than OpenCode's default 128k)
if 'models' not in config['provider']['cloudflare-workers-ai']:
    config['provider']['cloudflare-workers-ai']['models'] = {}

config['provider']['cloudflare-workers-ai']['models'].update({
    "@cf/meta/llama-3.3-70b-instruct-fp8-fast": {
        "limit": {"context": 24000, "output": 4096}
    },
    "@cf/deepseek-ai/deepseek-r1-distill-qwen-32b": {
        "limit": {"context": 80000, "output": 4096}
    },
    "@cf/qwen/qwen2.5-coder-32b-instruct": {
        "limit": {"context": 32000, "output": 4096}
    },
    "@cf/meta/llama-3.1-8b-instruct-fp8": {
        "limit": {"context": 32000, "output": 4096}
    },
    "@cf/meta/llama-3.2-3b-instruct": {
        "limit": {"context": 8192, "output": 2048}
    },
    "@cf/meta/llama-3.2-1b-instruct": {
        "limit": {"context": 8192, "output": 2048}
    }
})

# Configure automatic preflight compaction with safety buffer to avoid context overflow
config['compaction'] = {
    "auto": True,
    "keep": {
        "tokens": 4000
    },
    "buffer": 6000
}

# Delegate compaction to Google Gemini Flash (1M tokens) if Google is available
# so compaction never chokes on small Cloudflare model context limits
if 'google' in config.get('provider', {}):
    if 'agent' not in config or not isinstance(config['agent'], dict):
        config['agent'] = {}
    config['agent']['compaction'] = {
        "model": "google/gemini-2.5-flash"
    }

# Set default model if requested or if none exists
if default_model:
    config['model'] = default_model
elif 'model' not in config or not config['model']:
    config['model'] = 'cloudflare-workers-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast'

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
print(f"  -> Configured Cloudflare Workers AI provider and compaction in {config_file}")

# 2. Configure auth.json
auth_file = os.path.join(share_dir, 'auth.json')
try:
    with open(auth_file, 'r') as f:
        auth_data = json.load(f)
except Exception:
    auth_data = {}

auth_data['cloudflare-workers-ai'] = {
    "type": "api",
    "key": api_key,
    "metadata": {
        "accountId": account_id
    }
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

    # Clean up any stale/incomplete cloudflare exports first if needed
    lines = content.splitlines()
    filtered_lines = [
        l for l in lines
        if not (l.startswith('export CLOUDFLARE_ACCOUNT_ID=') or
                l.startswith('export CLOUDFLARE_API_KEY=') or
                l.startswith('export CLOUDFLARE_API_TOKEN='))
    ]

    new_entries = [
        f'export CLOUDFLARE_ACCOUNT_ID="{account_id}"',
        f'export CLOUDFLARE_API_KEY="{api_key}"',
        f'export CLOUDFLARE_API_TOKEN="{api_key}"'
    ]

    new_content = '\n'.join(filtered_lines).rstrip() + '\n\n# Added by Cloudflare Workers AI Opencode Setup\n' + '\n'.join(new_entries) + '\n'

    try:
        with open(rc_path, 'w') as f:
            f.write(new_content)
        print(f"  -> Updated environment variables in {rc_path}")
    except Exception as e:
        print(f"  -> Notice: could not write to {rc_path}: {e}")
PYEOF
}

setup_all_environments() {
    local account_id="$1"
    local api_key="$2"
    local default_model="$3"

    log_info "Configuring Cloudflare Workers AI credentials across environments..."

    # Collect all relevant home directories
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

    local seen_homes=()
    for h in "${target_homes[@]}"; do
        if [[ ! " ${seen_homes[*]} " =~ " ${h} " ]]; then
            seen_homes+=("$h")
            log_info "Setting up configuration for: $h"
            setup_cf_for_home "$h" "$account_id" "$api_key" "$default_model"
        fi
    done
}

# Main function
main() {
    echo -e "${MAGENTA}======================================================${NC}"
    echo -e "${CYAN} Cloudflare Workers AI Setup for OpenCode CLI${NC}"
    echo -e "${MAGENTA}======================================================${NC}"
    echo ""

    check_dependencies

    if ! check_opencode; then
        install_opencode
    fi
    echo ""

    ask_credentials
    echo ""

    ask_default_model
    echo ""

    test_connection
    echo ""

    setup_all_environments "$ACCOUNT_ID" "$API_KEY" "$DEFAULT_MODEL"
    echo ""

    log_info "======================================================"
    log_info "Setup Complete! ✅"
    log_info "======================================================"
    echo ""
    log_info "Top Free Cloudflare Workers AI Models Ready in OpenCode:"
    echo "  • cloudflare-workers-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast  (Flagship 70B Coding Agent)"
    echo "  • cloudflare-workers-ai/@cf/deepseek-ai/deepseek-r1-distill-qwen-32b (DeepSeek R1 Reasoning)"
    echo "  • cloudflare-workers-ai/@cf/qwen/qwen2.5-coder-32b-instruct       (Qwen Coding Specialist)"
    echo "  • cloudflare-workers-ai/@cf/qwen/qwen3.8-27b                      (Latest Qwen 3.8 Series)"
    echo "  • cloudflare-workers-ai/@cf/qwen/qwen3-30b-a3b-fp8                (Qwen 3 MoE Fast)"
    echo "  • cloudflare-workers-ai/@cf/qwen/qwq-32b                          (Qwq Reasoning Specialist)"
    echo "  • cloudflare-workers-ai/@cf/deepseek-ai/deepseek-v4-flash-0731   (DeepSeek V4 Flash)"
    echo "  • cloudflare-workers-ai/@cf/deepseek-ai/deepseek-v4-pro-0813     (DeepSeek V4 Pro)"
    echo "  • cloudflare-workers-ai/@cf/meta/llama-3.1-8b-instruct-fp8       (Lightweight & Ultra Fast)"
    echo "  • cloudflare-workers-ai/@cf/meta/llama-3.2-3b-instruct            (Ultra-low Neurons)"
    echo "  • cloudflare-workers-ai/@cf/meta/llama-4-scout-17b-16e-instruct   (Llama 4 Scout)"
    echo "  • cloudflare-workers-ai/@cf/mistralai/mistral-small-3.1-24b-instruct (Mistral Small 3.1)"
    echo "  • cloudflare-workers-ai/@cf/google/gemma-4-26b-a4b-it             (Google Gemma 4)"
    echo "  • cloudflare-workers-ai/@cf/openai/gpt-oss-120b                   (GPT OSS 120B)"
    echo "  • cloudflare-workers-ai/@cf/zai-org/glm-5.3-flash                 (GLM 5.3 Flash)"
    echo ""

    # Verify with OpenCode CLI if available
    if command -v opencode >/dev/null 2>&1; then
        log_info "Verifying models with OpenCode CLI..."
        if opencode models cloudflare-workers-ai >/dev/null 2>&1; then
            local count
            count=$(opencode models cloudflare-workers-ai | wc -l)
            log_info "OpenCode successfully recognized $count Cloudflare Workers AI models!"
        fi
    fi

    echo ""
    log_info "To use Cloudflare Workers AI in OpenCode:"
    log_info "  1. If using PRoot Distro, log in:"
    log_info "     proot-distro login debian"
    log_info "  2. Start OpenCode:"
    log_info "     opencode"
    log_info "  3. In chat, type /models to switch models interactively!"
    log_info "  Or run directly from CLI:"
    log_info "     opencode -m cloudflare-workers-ai/@cf/meta/llama-3.3-70b-instruct-fp8-fast"
    log_info "     opencode -m cloudflare-workers-ai/@cf/deepseek-ai/deepseek-r1-distill-qwen-32b"
    log_info "     opencode -m cloudflare-workers-ai/@cf/qwen/qwen2.5-coder-32b-instruct"
    echo ""
    log_info "Enjoy free Cloudflare Workers AI with OpenCode! 🚀"
}

main
