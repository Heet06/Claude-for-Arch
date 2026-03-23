#!/bin/bash
set -e

# Claude Desktop Auto-Update Script for Arch Linux
# This script checks for and installs new versions of Claude Desktop

# Allow custom install directory via environment variable
INSTALL_DIR="${CLAUDE_INSTALL_DIR:-$HOME/claude-desktop-build}"
# Backups go to a sibling directory relative to install location
BACKUP_DIR="$(dirname "$INSTALL_DIR")/claude-desktop-backups"
UPDATE_API="https://api.anthropic.com/api/desktop/win32/x64/msix/update"
DEVICE_ID="linux-build-$(uname -n)"
ELECTRON_RESOURCES_PATH=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

detect_electron_resources_dir() {
    local candidate
    local -a candidates=()

    # Optional manual override for non-standard layouts.
    if [ -n "${ELECTRON_RESOURCES_DIR:-}" ]; then
        if [ -d "$ELECTRON_RESOURCES_DIR" ]; then
            echo "${ELECTRON_RESOURCES_DIR%/}"
            return 0
        fi
        log_error "ELECTRON_RESOURCES_DIR is set but does not exist: $ELECTRON_RESOURCES_DIR"
        return 1
    fi

    # Prefer package metadata on Arch.
    if command -v pacman &>/dev/null; then
        while IFS= read -r pkg; do
            while IFS= read -r listed_path; do
                candidate="${listed_path%/}"
                [ -d "$candidate" ] && candidates+=("$candidate")
            done < <(pacman -Ql "$pkg" 2>/dev/null | awk '$2 ~ /\/resources\/?$/ { print $2 }')
        done < <(pacman -Qsq '^electron[0-9]*$|^electron$' 2>/dev/null)
    fi

    # Derive likely location from the active electron binary.
    local electron_bin real_electron_bin
    electron_bin="$(command -v electron 2>/dev/null || true)"
    if [ -n "$electron_bin" ]; then
        real_electron_bin="$(readlink -f "$electron_bin" 2>/dev/null || echo "$electron_bin")"
        candidates+=("$(dirname "$real_electron_bin")/resources")
        candidates+=("$(dirname "$(dirname "$real_electron_bin")")/resources")
    fi

    # Last-resort filesystem patterns used by Arch packages.
    for candidate in /usr/lib/electron/resources /usr/lib/electron*/resources; do
        [ -d "$candidate" ] && candidates+=("$candidate")
    done

    for candidate in "${candidates[@]}"; do
        if [ -d "$candidate" ]; then
            echo "${candidate%/}"
            return 0
        fi
    done

    log_error "Could not detect Electron resources directory"
    log_error "Set ELECTRON_RESOURCES_DIR manually, example: ELECTRON_RESOURCES_DIR=/usr/lib/electron39/resources"
    return 1
}

# Get current installed version
get_current_version() {
    local pkg_file="$INSTALL_DIR/claude-app/app/resources/package.json"
    local asar_file="$INSTALL_DIR/claude-app/app/resources/app.asar"

    # If package.json doesn't exist, extract entire asar to temp and copy it
    if [ ! -f "$pkg_file" ] && [ -f "$asar_file" ]; then
        # Log to stderr so it doesn't interfere with the version output
        echo -e "${YELLOW}[WARN]${NC} Extracting version info from current installation..." >&2

        # Extract entire asar to temp
        local temp_extract="/tmp/asar-extract-version-$$"
        mkdir -p "$temp_extract"

        (
            cd "$(dirname "$asar_file")" &&
                asar extract "$(basename "$asar_file")" "$temp_extract" 2>/dev/null
        )

        # Copy package.json if extraction succeeded
        if [ -f "$temp_extract/package.json" ]; then
            cp "$temp_extract/package.json" "$pkg_file"
        fi

        # Cleanup
        rm -rf "$temp_extract"
    fi

    # Now try to read version
    if [ -f "$pkg_file" ] && [ -s "$pkg_file" ]; then
        local version=$(grep -oP '"version":\s*"\K[^"]+' "$pkg_file" 2>/dev/null)
        echo "${version:-none}"
    else
        echo "none"
    fi
}

# Get update information from Anthropic's API
get_update_info() {
    curl -s "${UPDATE_API}?device_id=${DEVICE_ID}" 2>/dev/null
}

# Get latest available version from API
get_latest_version() {
    local response=$(get_update_info)
    echo "$response" | grep -oP '"currentRelease":\s*"\K[^"]+' | head -1
}

# Get download URL for latest version
get_download_url() {
    local response=$(get_update_info)
    echo "$response" | grep -oP '"url":\s*"\K[^"]+' | head -1
}

# Download the latest MSIX package
download_latest() {
    local download_url=$(get_download_url)

    if [ -z "$download_url" ]; then
        log_error "Could not get download URL from API"
        return 1
    fi

    log_info "Downloading from: $download_url"

    if curl -L -o "$INSTALL_DIR/Claude-new.msix" "$download_url"; then
        log_info "Download complete"
        return 0
    else
        log_error "Download failed"
        return 1
    fi
}

# Backup current installation
backup_current() {
    if [ -d "$INSTALL_DIR/claude-app" ]; then
        local backup_name="claude-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        log_info "Backing up current installation to $BACKUP_DIR/$backup_name"
        cp -r "$INSTALL_DIR/claude-app" "$BACKUP_DIR/$backup_name"

        # Keep only last 3 backups
        ls -t "$BACKUP_DIR" | tail -n +4 | while read backup; do
            rm -rf "$BACKUP_DIR/$backup"
        done
    fi
}

# Install new version
install_update() {
    local msix_file="$1"

    log_info "Extracting new version..."

    cd "$INSTALL_DIR"

    # Remove old installation
    rm -rf claude-app

    # Extract new MSIX
    7z x "$msix_file" -oclaude-app >/dev/null

    if [ ! -d "claude-app/app/resources" ]; then
        log_error "Extraction failed - resources directory not found"
        return 1
    fi

    log_info "Extracting MCP runtime files..."
    # Extract files from asar
    local resources_dir="$INSTALL_DIR/claude-app/app/resources"

    cd "$resources_dir"

    # Extract MCP runtime files to temp
    local temp_dir="/tmp/asar-extract-$$"
    asar extract app.asar "$temp_dir" 2>/dev/null || true

    # Create directory and copy MCP files
    mkdir -p .vite/build/mcp-runtime
    if [ -f "$temp_dir/.vite/build/mcp-runtime/nodeHost.js" ]; then
        cp "$temp_dir/.vite/build/mcp-runtime/nodeHost.js" .vite/build/mcp-runtime/
        cp "$temp_dir/.vite/build/mcp-runtime/window-shared.css" .vite/build/mcp-runtime/
        log_info "✓ MCP runtime files extracted"
    else
        log_warn "MCP extraction failed"
    fi
    rm -rf "$temp_dir"

    cd "$INSTALL_DIR"

    if [ -z "$ELECTRON_RESOURCES_PATH" ]; then
        ELECTRON_RESOURCES_PATH="$(detect_electron_resources_dir)" || return 1
        log_info "Using Electron resources: $ELECTRON_RESOURCES_PATH"
    fi

    log_info "Updating symlinks in system electron..."

    # Remove old symlinks/files
    sudo rm -f "$ELECTRON_RESOURCES_PATH"/*.json 2>/dev/null
    sudo rm -rf "$ELECTRON_RESOURCES_PATH"/.vite 2>/dev/null
    sudo rm -f "$ELECTRON_RESOURCES_PATH"/app.asar 2>/dev/null

    # Create new symlinks
    for file in claude-app/app/resources/*.json; do
        sudo ln -sf "$INSTALL_DIR/$file" "$ELECTRON_RESOURCES_PATH"/
    done

    # Symlink the asar
    sudo ln -sf "$INSTALL_DIR/claude-app/app/resources/app.asar" "$ELECTRON_RESOURCES_PATH"/app.asar

    # Symlink the .vite directory
    sudo ln -sf "$INSTALL_DIR/claude-app/app/resources/.vite" "$ELECTRON_RESOURCES_PATH"/.vite

    log_info "✓ Symlinks updated"

    log_info "Installation complete!"
    log_info "Note: Your custom claude-desktop.sh launcher has been preserved"

    # Update icon path in launcher to point to latest icon
    local launcher="$INSTALL_DIR/claude-desktop.sh"
    local icon_path=""

    # Try to find best icon in order of preference
    if [ -f "$INSTALL_DIR/claude-app/assets/icon.png" ]; then
        icon_path="$INSTALL_DIR/claude-app/assets/icon.png"
    elif [ -f "$INSTALL_DIR/claude-app/app/resources/claude-screen.png" ]; then
        icon_path="$INSTALL_DIR/claude-app/app/resources/claude-screen.png"
    fi

    # Update ELECTRON_ICON in launcher if we found an icon
    if [ -n "$icon_path" ] && [ -f "$launcher" ]; then
        # Update or add ELECTRON_ICON export
        if grep -q "^export ELECTRON_ICON=" "$launcher"; then
            sed -i "s|^export ELECTRON_ICON=.*|export ELECTRON_ICON=\"$icon_path\"|" "$launcher"
            log_info "✓ Updated launcher icon path"
        else
            # Add ELECTRON_ICON after ELECTRON_RESOURCES_PATH line
            sed -i "/^export ELECTRON_RESOURCES_PATH=/a export ELECTRON_ICON=\"$icon_path\"" "$launcher"
            log_info "✓ Added icon path to launcher"
        fi
    fi

    # Update desktop integration with new icons
    if [ -x "$INSTALL_DIR/update-claude-integration.sh" ]; then
        log_info "Updating desktop integration..."
        "$INSTALL_DIR/update-claude-integration.sh" >/dev/null 2>&1 || true
    fi

    return 0
}

# Main update process
perform_update() {
    local current_version=$(get_current_version)
    log_info "Current version: $current_version"

    local latest_version=$(get_latest_version)

    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        log_error "Could not fetch latest version information"
        return 1
    fi

    log_info "Latest version: $latest_version"

    # Compare versions (simple string comparison is fine for Claude's version format)
    # If we couldn't get latest version, don't claim we're up to date
    if [ -z "$latest_version" ]; then
        log_error "Could not determine latest version"
        return 1
    fi

    if [ "$current_version" = "$latest_version" ]; then
        log_info "Already up to date!"
        return 0
    fi

    log_info "New version available: $latest_version"

    # Ask for confirmation unless --auto flag is set
    if [ "$1" != "--auto" ]; then
        read -p "Do you want to update? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Update cancelled"
            return 0
        fi
    fi

    # Close running Claude instance
    log_info "Closing Claude Desktop..."
    pkill -f "electron.*app.asar" 2>/dev/null || true
    sleep 2

    # Backup current installation
    backup_current

    # Download new version
    if ! download_latest; then
        log_error "Download failed - please update manually"
        return 1
    fi

    # Install update
    if install_update "$INSTALL_DIR/Claude-new.msix"; then
        rm "$INSTALL_DIR/Claude-new.msix"
        log_info "Update successful! Version $latest_version installed"
        log_info "You can now restart Claude Desktop"
        return 0
    else
        log_error "Installation failed - restoring from backup"
        # Restore from backup
        local latest_backup=$(ls -t "$BACKUP_DIR" | head -1)
        if [ -n "$latest_backup" ]; then
            rm -rf "$INSTALL_DIR/claude-app"
            cp -r "$BACKUP_DIR/$latest_backup" "$INSTALL_DIR/claude-app"
            log_info "Restored from backup"
        fi
        return 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()

    for cmd in curl 7z node asar; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Install with: sudo pacman -S curl p7zip nodejs asar"
        exit 1
    fi

    # Note: Uses system asar command, not npm package
}

# Show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --auto       Update automatically without prompting"
    echo "  --check      Only check for updates, don't install"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Check and prompt for update"
    echo "  $0 --auto       # Update automatically"
    echo "  $0 --check      # Just check version"
}

# Main execution
main() {
    case "${1:-}" in
        --help | -h)
            usage
            exit 0
            ;;
        --check)
            check_dependencies
            local current=$(get_current_version)
            local latest=$(get_latest_version)
            echo "Current version: $current"
            echo "Latest version: $latest"
            if [ "$current" != "$latest" ]; then
                exit 1 # Update available
            else
                exit 0 # Up to date
            fi
            ;;
        --auto)
            check_dependencies
            perform_update --auto
            ;;
        "")
            check_dependencies
            perform_update
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
