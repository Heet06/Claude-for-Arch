#!/bin/bash
set -e

# Claude Desktop Installation Script - Simple & Working Approach
# This keeps the asar file intact and runs from it (as designed)

INSTALL_DIR="$HOME/claude-desktop-build"
DOWNLOAD_URL="https://claude.ai/api/desktop/win32/x64/msix/latest/redirect"
ELECTRON_RESOURCES_PATH=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

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
    if command -v pacman &> /dev/null; then
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

echo "=== Claude Desktop Installation ==="
echo

# Check dependencies
log_info "Checking dependencies..."
missing=()
for cmd in curl 7z electron asar xdpyinfo wmctrl; do
    if ! command -v $cmd &> /dev/null; then
        missing+=($cmd)
    fi
done

if [ ${#missing[@]} -ne 0 ]; then
    log_error "Missing: ${missing[*]}"
    echo "Install with: sudo pacman -S electron curl p7zip asar xorg-xdpyinfo wmctrl"
    exit 1
fi

ELECTRON_RESOURCES_PATH="$(detect_electron_resources_dir)" || exit 1
log_info "Using Electron resources: $ELECTRON_RESOURCES_PATH"

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download Claude
log_info "Downloading Claude Desktop..."
curl -L -o Claude.msix "$DOWNLOAD_URL"

# Extract MSIX
log_info "Extracting..."
rm -rf claude-app
7z x Claude.msix -oclaude-app > /dev/null

# Extract MCP runtime files (required for MCP to work)
log_info "Extracting MCP runtime files..."
cd claude-app/app/resources

# Check if asar command is available
if ! command -v asar &> /dev/null; then
    log_error "asar command not found. Install with: sudo pacman -S asar"
    exit 1
fi

# Extract MCP runtime files to temp
temp_dir="/tmp/asar-extract-$$"
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

# Create symlinks in system electron (instead of copying files)
log_info "Creating symlinks in system electron..."

# Remove any existing files/symlinks
sudo rm -f "$ELECTRON_RESOURCES_PATH"/*.json 2>/dev/null
sudo rm -rf "$ELECTRON_RESOURCES_PATH"/.vite 2>/dev/null
sudo rm -f "$ELECTRON_RESOURCES_PATH"/app.asar 2>/dev/null

# Symlink locale files
for file in claude-app/app/resources/*.json; do
    sudo ln -sf "$INSTALL_DIR/$file" "$ELECTRON_RESOURCES_PATH"/
done

# Symlink the asar
sudo ln -sf "$INSTALL_DIR/claude-app/app/resources/app.asar" "$ELECTRON_RESOURCES_PATH"/app.asar

# Symlink the .vite directory (contains MCP runtime)
sudo ln -sf "$INSTALL_DIR/claude-app/app/resources/.vite" "$ELECTRON_RESOURCES_PATH"/.vite

log_info "✓ Symlinks created"

# Create launcher
log_info "Creating launcher..."
cat > claude-desktop.sh << 'LAUNCHER'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

rm -f ~/.config/Claude/window-state*.json 2>/dev/null

export ELECTRON_DISABLE_SECURITY_WARNINGS=1
export GDK_BACKEND=x11
export ELECTRON_OZONE_PLATFORM_HINT=auto
export LIBGL_ALWAYS_SOFTWARE=1

# Run electron with the asar file (as designed)
cd "$SCRIPT_DIR/claude-app/app"

electron resources/app.asar \
  --enable-features=UseOzonePlatform \
  --ozone-platform=x11 \
  --disable-gpu \
  --disable-gpu-compositing \
  "$@" 2> >(grep -v "ERROR:dbus\|ComputerUseTcc\|mime.cache" >&2) &

sleep 2
SCREEN_WIDTH=$(xdpyinfo | grep dimensions | awk '{print $2}' | cut -d'x' -f1)
SCREEN_HEIGHT=$(xdpyinfo | grep dimensions | awk '{print $2}' | cut -d'x' -f2)
WIDTH=$(((SCREEN_WIDTH * 95 / 100) + 100))
HEIGHT=$(((SCREEN_HEIGHT * 95 / 100) - 40))
X=$(( (SCREEN_WIDTH - WIDTH) / 2 ))
Y=$(( (SCREEN_HEIGHT - HEIGHT) / 2 ))
wmctrl -r "Claude" -e 0,$X,$Y,$WIDTH,$HEIGHT 2>/dev/null || true
sleep 0.5
wmctrl -r "Claude" -b add,maximized_vert,maximized_horz 2>/dev/null || true
LAUNCHER

chmod +x claude-desktop.sh

# Desktop integration
log_info "Setting up desktop integration..."
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/claude-desktop.desktop << EOF
[Desktop Entry]
Name=Claude Desktop
Comment=Claude AI Assistant
Exec=$INSTALL_DIR/claude-desktop.sh %u
Icon=$INSTALL_DIR/claude-app/app/resources/claude-screen.png
Terminal=false
Type=Application
Categories=Development;Utility;Network;Office;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
EOF

chmod +x ~/.local/share/applications/claude-desktop.desktop

mkdir -p ~/.local/share/icons/hicolor/256x256/apps
cp claude-app/app/resources/claude-screen.png ~/.local/share/icons/hicolor/256x256/apps/claude.png

update-desktop-database ~/.local/share/applications/ 2>/dev/null || true
xdg-mime default claude-desktop.desktop x-scheme-handler/claude 2>/dev/null || true

# Create MCP config if needed
if [ ! -f ~/.config/Claude/claude_desktop_config.json ]; then
    mkdir -p ~/.config/Claude
    cat > ~/.config/Claude/claude_desktop_config.json << 'CONFIG'
{
  "mcpServers": {}
}
CONFIG
fi

echo
log_info "=== Installation Complete ==="
echo
echo "Launch with: $INSTALL_DIR/claude-desktop.sh"
echo "Or press Ctrl+Alt+Space"
echo
