#!/bin/bash
# XKiro Setup Script for Opencode
# Fully automatic setup - works on Termux, Proot, Debian 13/12
# Creates/fixes models.json and configures all 35 free models

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

# Fully standalone: setup xkiro in opencode.jsonc, auth.json, models.json and shell rc
setup_xkiro_models() {
    local api_key="$1"
    log_info "Configuring XKiro provider, models, and credentials..."
    
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
    export XKIRO_API_KEY="$api_key"
    
    python3 << 'PYEOFSCRIPT'
import json
import os

USER_HOME = os.environ.get('USER_HOME', os.path.expanduser('~'))
API_KEY = os.environ.get('XKIRO_API_KEY', '')

# All 35 free model definitions to add under xkiro
all_35_models = {
    # GLM model (1)
    "z-ai/glm-5.3": {
        "id": "z-ai/glm-5.3",
        "name": "GLM-5.3",
        "description": "GLM-5.3 model via XKiro API",
        "family": "glm",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": True,
        "limit": {"context": 1000000, "output": 131072},
        "cost": {"input": 1.4, "output": 4.4, "cache_read": 0.26}
    },
    # Minimax models (8 free tier)
    "minimax/minimax-m3:free": {
        "id": "minimax/minimax-m3:free",
        "name": "Minimax-m3:free",
        "description": "Minimax M3 model (free tier) for testing",
        "family": "minimax",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "minimax/minimax-m2.7:free": {
        "id": "minimax/minimax-m2.7:free",
        "name": "Minimax-m2.7:free",
        "description": "Minimax M2.7 model (free tier) for testing",
        "family": "minimax",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "minimax/minimax-m2.7-highspeed:free": {
        "id": "minimax/minimax-m2.7-highspeed:free",
        "name": "Minimax-m2.7-highspeed:free",
        "description": "Minimax M2.7 highspeed (free tier) for testing",
        "family": "minimax",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "minimax/minimax-m2.5:free": {
        "id": "minimax/minimax-m2.5:free",
        "name": "Minimax-m2.5:free",
        "description": "Minimax M2.5 model (free tier) for testing",
        "family": "minimax",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "minimax/minimax-m2.5-highspeed:free": {
        "id": "minimax/minimax-m2.5-highspeed:free",
        "name": "Minimax-m2.5-highspeed:free",
        "description": "Minimax M2.5 highspeed (free tier) for testing",
        "family": "minimax",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "minimax/minimax-m2.1:free": {
        "id": "minimax/minimax-m2.1:free",
        "name": "Minimax-m2.1:free",
        "description": "Minimax M2.1 model (free tier) for testing",
        "family": "minimax",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "minimax/minimax-m2.1-highspeed:free": {
        "id": "minimax/minimax-m2.1-highspeed:free",
        "name": "Minimax-m2.1-highspeed:free",
        "description": "Minimax M2.1 highspeed (free tier) for testing",
        "family": "minimax",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "minimax/minimax-m2:free": {
        "id": "minimax/minimax-m2:free",
        "name": "Minimax-m2:free",
        "description": "Minimax M2 model (free tier) for testing",
        "family": "minimax",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": False,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    # MistralAI models (8)
    "mistralai/mistral-large-2512": {
        "id": "mistralai/mistral-large-2512",
        "name": "Mistral-large-2512",
        "description": "Mistral-large-2512 via XKiro API",
        "family": "mistralai",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": True,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "mistralai/mistral-medium-3.5": {
        "id": "mistralai/mistral-medium-3.5",
        "name": "Mistral-medium-3.5",
        "description": "Mistral-medium-3.5 via XKiro API",
        "family": "mistralai",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": True,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "mistralai/mistral-small-2603": {
        "id": "mistralai/mistral-small-2603",
        "name": "Mistral-small-2603",
        "description": "Mistral-small-2603 via XKiro API",
        "family": "mistralai",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": True,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "mistralai/codestral-2508": {
        "id": "mistralai/codestral-2508",
        "name": "Codestral-2508",
        "description": "Codestral-2508 via XKiro API",
        "family": "mistralai",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": True,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "mistralai/devstral-medium": {
        "id": "mistralai/devstral-medium",
        "name": "Devstral-medium",
        "description": "Devstral-medium via XKiro API",
        "family": "mistralai",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": True,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "mistralai/ministral-14b": {
        "id": "mistralai/ministral-14b",
        "name": "Ministral-14b",
        "description": "Ministral-14b via XKiro API",
        "family": "mistralai",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": True,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "mistralai/ministral-8b": {
        "id": "mistralai/ministral-8b",
        "name": "Ministral-8b",
        "description": "Ministral-8b via XKiro API",
        "family": "mistralai",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": True,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "mistralai/ministral-3b": {
        "id": "mistralai/ministral-3b",
        "name": "Ministral-3b",
        "description": "Ministral-3b via XKiro API",
        "family": "mistralai",
        "attachment": False,
        "reasoning": True,
        "reasoning_options": [
            {"type": "toggle"},
            {"type": "budget_tokens"}
        ],
        "tool_call": True,
        "structured_output": True,
        "temperature": True,
        "release_date": "2024-01-01",
        "last_updated": "2024-01-01",
        "modalities": {"input": ["text"], "output": ["text"]},
        "open_weights": True,
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    # Qwen models (18 free tier)
    "qwen/qwen3.8-max:free": {
        "id": "qwen/qwen3.8-max:free",
        "name": "Qwen3.8-max:free",
        "description": "Qwen3.8-max free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.7-max:free": {
        "id": "qwen/qwen3.7-max:free",
        "name": "Qwen3.7-max:free",
        "description": "Qwen3.7-max free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.7-plus:free": {
        "id": "qwen/qwen3.7-plus:free",
        "name": "Qwen3.7-plus:free",
        "description": "Qwen3.7-plus free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.7-flash:free": {
        "id": "qwen/qwen3.7-flash:free",
        "name": "Qwen3.7-flash:free",
        "description": "Qwen3.7-flash free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.6-plus:free": {
        "id": "qwen/qwen3.6-plus:free",
        "name": "Qwen3.6-plus:free",
        "description": "Qwen3.6-plus free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.6-max-preview:free": {
        "id": "qwen/qwen3.6-max-preview:free",
        "name": "Qwen3.6-max-preview:free",
        "description": "Qwen3.6-max-preview free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.6-27b:free": {
        "id": "qwen/qwen3.6-27b:free",
        "name": "Qwen3.6-27b:free",
        "description": "Qwen3.6-27b free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.5-plus:free": {
        "id": "qwen/qwen3.5-plus:free",
        "name": "Qwen3.5-plus:free",
        "description": "Qwen3.5-plus free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.5-omni-plus:free": {
        "id": "qwen/qwen3.5-omni-plus:free",
        "name": "Qwen3.5-omni-plus:free",
        "description": "Qwen3.5-omni-plus free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.6-35b-a3b:free": {
        "id": "qwen/qwen3.6-35b-a3b:free",
        "name": "Qwen3.6-35b-a3b:free",
        "description": "Qwen3.6-35b-a3b free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.5-flash:free": {
        "id": "qwen/qwen3.5-flash:free",
        "name": "Qwen3.5-flash:free",
        "description": "Qwen3.5-flash free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.5-397b-a17b:free": {
        "id": "qwen/qwen3.5-397b-a17b:free",
        "name": "Qwen3.5-397b-a17b:free",
        "description": "Qwen3.5-397b-a17b free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3.5-omni-flash:free": {
        "id": "qwen/qwen3.5-omni-flash:free",
        "name": "Qwen3.5-omni-flash:free",
        "description": "Qwen3.5-omni-flash free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3-max:free": {
        "id": "qwen/qwen3-max:free",
        "name": "Qwen3-max:free",
        "description": "Qwen3-max free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen-plus-2025-07-28:free": {
        "id": "qwen/qwen-plus-2025-07-28:free",
        "name": "Qwen-plus-2025-07-28:free",
        "description": "Qwen-plus-2025-07-28 free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3-coder-plus:free": {
        "id": "qwen/qwen3-coder-plus:free",
        "name": "Qwen3-coder-plus:free",
        "description": "Qwen3-coder-plus free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3-vl-plus:free": {
        "id": "qwen/qwen3-vl-plus:free",
        "name": "Qwen3-vl-plus:free",
        "description": "Qwen3-vl-plus free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
        "cost": {"input": 0, "output": 0, "cache_read": 0}
    },
    "qwen/qwen3-omni-flash:free": {
        "id": "qwen/qwen3-omni-flash:free",
        "name": "Qwen3-omni-flash:free",
        "description": "Qwen3-omni-flash free tier via XKiro API",
        "family": "qwen",
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
        "limit": {"context": 100000, "output": 8192},
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

config_data['provider']['xkiro'] = {
    "name": "XKiro",
    "npm": "@ai-sdk/openai-compatible",
    "env": ["XKIRO_API_KEY"],
    "options": {
        "baseURL": "https://api.xkiro.com/v1",
        "apiKey": API_KEY
    },
    "models": all_35_models
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

auth_data['xkiro'] = {
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

if 'xkiro' not in data or not isinstance(data['xkiro'], dict):
    data['xkiro'] = {
        'id': 'xkiro',
        'env': ['XKIRO_API_KEY'],
        'npm': '@ai-sdk/openai-compatible',
        'api': 'https://api.xkiro.com/v1',
        'name': 'XKiro',
        'doc': 'https://xkiro.com',
        'models': {}
    }

if 'models' not in data['xkiro'] or not isinstance(data['xkiro']['models'], dict):
    data['xkiro']['models'] = {}

for model_key, model_config in all_35_models.items():
    data['xkiro']['models'][model_key] = model_config

with open(models_json, 'w') as f:
    json.dump(data, f, indent=2)
print(f"  -> Injected 35 models into {models_json}")

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
    if 'export XKIRO_API_KEY=' not in content:
        entries.append(f'export XKIRO_API_KEY="{API_KEY}"')
    if 'export OPENCODE_DISABLE_MODELS_FETCH=' not in content:
        entries.append('export OPENCODE_DISABLE_MODELS_FETCH=1')
    
    if entries:
        try:
            with open(rc_path, 'a') as f:
                f.write('\n# Added by XKiro Opencode Setup\n' + '\n'.join(entries) + '\n')
            print(f"  -> Added environment exports to {rc_path}")
        except Exception:
            pass
PYEOFSCRIPT
    
    log_info "Setup finished for $user_home"
}

# Ask for XKiro API key
ask_api_key() {
    log_info "Please enter your XKiro API key"
    read -p "XKIRO_API_KEY: " XKIRO_API_KEY
    
    if [ -z "$XKIRO_API_KEY" ]; then
        log_error "API key cannot be empty"
        exit 1
    fi
    
    # Export in current subshell session
    export XKIRO_API_KEY="$XKIRO_API_KEY"
    export OPENCODE_DISABLE_MODELS_FETCH=1
    
    log_info "XKiro API key received"
}

# Main script execution
main() {
    log_info "========================================"
    log_info "XKiro Opencode Setup Script"
    log_info "========================================"
    log_info ""
    
    # Check if opencode is installed
    if ! check_opencode; then
        install_opencode
    fi
    
    log_info "Opencode is ready"
    log_info ""
    
    # Ask for API key first so it can be written to all configs
    ask_api_key
    log_info ""
    
    # Setup XKiro models, config, auth, and shell profiles
    setup_xkiro_models "$XKIRO_API_KEY"
    
    log_info ""
    log_info "========================================"
    log_info "Setup Complete! ✅"
    log_info "========================================"
    log_info ""
    log_info "Your XKiro API is now configured with 35 free models:"
    log_info ""
    
    # List available xkiro models
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
            models = list(d.get('provider', {}).get('xkiro', {}).get('models', {}).keys())
            if not models and 'xkiro' in d:
                models = list(d['xkiro'].get('models', {}).keys())
            if models:
                for i, m in enumerate(models, 1):
                    print(f'  {i}. {m}')
                break
        except Exception:
            pass
" | head -35
    
    log_info ""
    log_info "⚠️  To use in OpenCode:"
    log_info "  1. If you run in proot-distro, log in:"
    log_info "     proot-distro login debian"
    log_info "  2. Start OpenCode:"
    log_info "     opencode"
    log_info "  3. Type /models and search 'xkiro' to see all 35 models!"
    log_info ""
    log_info "Happy coding! 🚀"
}

# Run main function
main