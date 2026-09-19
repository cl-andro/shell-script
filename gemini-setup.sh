#!/bin/bash
# ==============================================================================
# Gemini (Google AI Studio) Setup Script for OpenCode CLI
# Works on: Termux, PRoot Distro (Debian 13/12, Ubuntu), Native Linux
# Configures: Google AI Studio API Key & Free Models for OpenCode Agent
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Ask for Google AI Studio API key
ask_api_key() {
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}Google AI Studio (Gemini) API Key Configuration${NC}"
    echo -e "${CYAN}Get a free key at: https://aistudio.google.com/apikey${NC}"
    echo -e "${CYAN}======================================================${NC}"
    
    if [ -n "$GEMINI_API_KEY" ]; then
        read -p "Found existing GEMINI_API_KEY. Use this key? (y/n) [y]: " use_existing
        if [[ "$use_existing" =~ ^[Yy]$ || -z "$use_existing" ]]; then
            API_KEY="$GEMINI_API_KEY"
        fi
    fi
    
    if [ -z "$API_KEY" ]; then
        read -p "Enter your Google AI Studio API Key: " API_KEY
    fi
    
    # Trim whitespace
    API_KEY=$(echo "$API_KEY" | xargs)
    
    if [ -z "$API_KEY" ]; then
        log_error "API key cannot be empty!"
        exit 1
    fi
    
    # Export in current session
    export GEMINI_API_KEY="$API_KEY"
    export GOOGLE_GENERATIVE_AI_API_KEY="$API_KEY"
    export GOOGLE_API_KEY="$API_KEY"
}

# Configure Gemini for target home directories
setup_gemini_for_home() {
    local user_home="$1"
    local api_key="$2"
    
    export TARGET_USER_HOME="$user_home"
    export TARGET_API_KEY="$api_key"
    
    python3 << 'PYEOF'
import os
import json

user_home = os.environ.get('TARGET_USER_HOME', os.path.expanduser('~'))
api_key = os.environ.get('TARGET_API_KEY', '')

if not user_home or not api_key:
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

# Google provider configuration
if 'google' not in config['provider'] or not isinstance(config['provider']['google'], dict):
    config['provider']['google'] = {}

if 'options' not in config['provider']['google'] or not isinstance(config['provider']['google']['options'], dict):
    config['provider']['google']['options'] = {}

config['provider']['google']['options']['apiKey'] = api_key

# Set default model to gemini-2.5-flash if none specified
if 'model' not in config or not config['model']:
    config['model'] = 'google/gemini-2.5-flash'

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
print(f"  -> Configured Google provider in {config_file}")

# 2. Configure auth.json
auth_file = os.path.join(share_dir, 'auth.json')
try:
    with open(auth_file, 'r') as f:
        auth_data = json.load(f)
except Exception:
    auth_data = {}

auth_data['google'] = {
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
    
    entries = []
    if 'export GEMINI_API_KEY=' not in content:
        entries.append(f'export GEMINI_API_KEY="{api_key}"')
    if 'export GOOGLE_GENERATIVE_AI_API_KEY=' not in content:
        entries.append(f'export GOOGLE_GENERATIVE_AI_API_KEY="{api_key}"')
    if 'export GOOGLE_API_KEY=' not in content:
        entries.append(f'export GOOGLE_API_KEY="{api_key}"')
    
    if entries:
        try:
            with open(rc_path, 'a') as f:
                f.write('\n# Added by Gemini Opencode Setup\n' + '\n'.join(entries) + '\n')
            print(f"  -> Added environment variables to {rc_path}")
        except Exception:
            pass
PYEOF
}

setup_all_gemini() {
    local api_key="$1"
    log_info "Configuring Google AI Studio credentials across environments..."
    
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
            setup_gemini_for_home "$h" "$api_key"
        fi
    done
}

# Main function
main() {
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${GREEN}Google AI Studio (Gemini) Setup for OpenCode${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo ""
    
    check_dependencies
    
    if ! check_opencode; then
        install_opencode
    fi
    echo ""
    
    ask_api_key
    echo ""
    
    setup_all_gemini "$API_KEY"
    echo ""
    
    log_info "======================================================"
    log_info "Setup Complete! ✅"
    log_info "======================================================"
    echo ""
    log_info "Popular free Google Gemini models configured for OpenCode:"
    echo "  • google/gemini-2.5-flash          (Fast, multimodal, high quota)"
    echo "  • google/gemini-2.5-pro            (Complex coding & reasoning)"
    echo "  • google/gemini-2.5-flash-lite     (Ultra fast, lightweight)"
    echo "  • google/gemini-3.8-flash          (Latest high-capability flash)"
    echo "  • google/gemini-3.7-flash          (High performance flash)"
    echo "  • google/gemini-flash-latest       (Always points to latest flash)"
    echo "  • google/gemma-4-31b-it            (Open weight instruction model)"
    echo "  • google/gemma-4-26b-a4b-it        (MoE open model)"
    echo ""
    
    # Verify with opencode if available
    if command -v opencode >/dev/null 2>&1; then
        log_info "Verifying models with OpenCode CLI..."
        if opencode models google >/dev/null 2>&1; then
            log_info "OpenCode successfully verified $(opencode models google | wc -l) Google models!"
        fi
    fi
    
    echo ""
    log_info "To start using Gemini in OpenCode:"
    log_info "  1. If using PRoot Distro, log in:"
    log_info "     proot-distro login debian"
    log_info "  2. Start OpenCode:"
    log_info "     opencode"
    log_info "  3. In chat, type /models and select your Gemini model (e.g. google/gemini-2.5-flash)!"
    log_info "  Or run directly from CLI:"
    log_info "     opencode -m google/gemini-2.5-flash"
    echo ""
    log_info "Happy coding with Gemini & OpenCode! 🚀"
}

main
