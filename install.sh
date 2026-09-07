#!/usr/bin/env bash

# VRCOSC automated installer, updater, and runner setup script for Bazzite / Linux
set -euo pipefail

# Visual styling
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0;0m' # No Color

readonly DISCORD_INVITE="https://discord.gg/vrcosc-1000862183963496519"
readonly DISCORD_THREAD="https://discord.com/channels/1000862183963496519/1466540047149957374"
readonly ICON_URL="https://raw.githubusercontent.com/VolcanicArts/VRCOSC/main/Logo.png"

# Default state variables (configured solely via command-line arguments)
VRCOSC_BRANCH="live" # live or beta
FORCE_INSTALL=0
UNINSTALL_MODE=0
BACKUP_MODE=0
DRY_RUN=0
SKIP_FIREWALL=0
VRC_COMPATDATA=""

log_info()    { echo -e "${BLUE}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_warn()    { echo -e "${YELLOW}$*${NC}"; }
log_error()   { echo -e "${RED}$*${NC}"; }

on_error() {
    local exit_code="$?"
    local line_no="$1"
    echo ""
    log_error "============================================================"
    log_error " Installation encountered an error (exit code $exit_code at line $line_no)!"
    log_error "============================================================"
    echo -e "${YELLOW}Need help or ran into an unexpected bug? Join the VRCOSC Discord:${NC}"
    echo -e "  * Server Invite:  ${CYAN}${DISCORD_INVITE}${NC}"
    echo -e "  * Linux Thread:   ${CYAN}${DISCORD_THREAD}${NC}"
    echo ""
    exit "$exit_code"
}

trap 'on_error $LINENO' ERR

print_usage() {
    echo -e "${BOLD}VRCOSC Linux Installer & Manager${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  bash install.sh [OPTIONS]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  -b, --backup              Create a high-compression backup of VRCOSC configs & prefix registries to Desktop"
    echo "  -f, --force               Force re-download and re-installation of .NET and VRCOSC"
    echo "      --branch <live|beta>  Specify release channel to install (default: live)"
    echo "  -u, --uninstall           Uninstall VRCOSC binaries, launcher script, and desktop shortcut"
    echo "      --dry-run             Simulate actions without writing files or running installers"
    echo "      --skip-firewall       Do not attempt firewall port configuration"
    echo "      --prefix <PATH>       Explicitly specify the VRChat compatdata/438100 folder"
    echo "  -h, --help                Show this help message"
}

parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -b|--backup)
                BACKUP_MODE=1
                shift
                ;;
            -f|--force)
                FORCE_INSTALL=1
                shift
                ;;
            -u|--uninstall)
                UNINSTALL_MODE=1
                shift
                ;;
            --branch)
                if [ -n "${2:-}" ]; then
                    VRCOSC_BRANCH="$2"
                    shift 2
                else
                    log_error "Error: --branch requires an argument (live or beta)."
                    exit 1
                fi
                ;;
            --prefix)
                if [ -n "${2:-}" ]; then
                    VRC_COMPATDATA="$2"
                    shift 2
                else
                    log_error "Error: --prefix requires a directory path."
                    exit 1
                fi
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --skip-firewall)
                SKIP_FIREWALL=1
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_warn "Unknown argument: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

check_dependencies() {
    log_info "Verifying dependencies..."
    local missing=()
    for cmd in protontricks curl unzip; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Error: The following required dependencies are missing: ${missing[*]}"
        exit 1
    fi
}

locate_vrchat_prefix() {
    log_info "Locating VRChat Proton prefix..."

    if [ -n "$VRC_COMPATDATA" ]; then
        VRC_COMPATDATA="${VRC_COMPATDATA/#\~/$HOME}"
        if [ -d "$VRC_COMPATDATA/pfx" ]; then
            log_success "Using pre-configured VRChat prefix: $VRC_COMPATDATA"
            return 0
        elif [ -d "$VRC_COMPATDATA/compatdata/438100/pfx" ]; then
            VRC_COMPATDATA="$VRC_COMPATDATA/compatdata/438100"
            log_success "Using pre-configured VRChat prefix: $VRC_COMPATDATA"
            return 0
        fi
    fi

    local candidate_paths=(
        "$HOME/.local/share/Steam"
        "$HOME/.steam/steam"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
        "$HOME/.var/app/com.valvesoftware.Steam/.steam/steam"
        "/run/media/system/Data/Games/Steam"
        "/media/media-automount/Data/Games/Steam"
    )

    # Automatically parse libraryfolders.vdf to find secondary & external drives
    for vdf in "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" \
               "$HOME/.steam/steam/steamapps/libraryfolders.vdf" \
               "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf"; do
        if [ -f "$vdf" ]; then
            while IFS= read -r line; do
                if [[ "$line" =~ \"path\"[[:space:]]*\"([^\"]+)\" ]]; then
                    candidate_paths+=("${BASH_REMATCH[1]}")
                fi
            done < "$vdf"
        fi
    done

    # Probe candidates for app 438100 prefix
    for p in "${candidate_paths[@]}"; do
        for check_dir in "$p" "$p/steamapps"; do
            if [ -d "$check_dir/compatdata/438100/pfx" ]; then
                VRC_COMPATDATA="$check_dir/compatdata/438100"
                log_success "Found VRChat compatibility data at: $VRC_COMPATDATA"
                return 0
            fi
        done
    done

    # Fallback to interactive user input if available
    log_warn "Could not automatically locate the VRChat (438100) Proton prefix."
    if [ -t 0 ]; then
        while [ -z "$VRC_COMPATDATA" ]; do
            log_info "Please enter the path to your SteamLibrary or the 438100 compatdata folder:"
            read -r -p "Path: " user_path
            user_path="${user_path/#\~/$HOME}"

            if [ -d "$user_path/pfx" ] && [[ "$user_path" == *"438100"* ]]; then
                VRC_COMPATDATA="$user_path"
            elif [ -d "$user_path/compatdata/438100/pfx" ]; then
                VRC_COMPATDATA="$user_path/compatdata/438100"
            elif [ -d "$user_path/steamapps/compatdata/438100/pfx" ]; then
                VRC_COMPATDATA="$user_path/steamapps/compatdata/438100"
            else
                log_error "Invalid path. Could not find 'pfx' folder for app 438100 under '$user_path'. Please try again."
            fi
        done
        log_success "Using VRChat prefix at: $VRC_COMPATDATA"
    else
        log_error "Error: Running non-interactively and prefix was not found."
        echo "Pass --prefix <PATH> explicitly."
        exit 1
    fi
}

create_backup() {
    log_info "Initiating VRCOSC and prefix backup..."
    locate_vrchat_prefix

    local desktop_dir
    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
    mkdir -p "$desktop_dir"

    local timestamp
    timestamp="$(date +%s)"
    local stage_dir="/tmp/vrcosc_backup_${timestamp}"
    mkdir -p "$stage_dir"

    # Collect important user configurations and registry states
    local items_found=0

    # 1. Config directories (Roaming/VRCOSC, Roaming/VRCOSC-Beta, Roaming/VRCOSC-Dev)
    for u in "$VRC_COMPATDATA/pfx/drive_c/users/"*; do
        if [ -d "$u/AppData/Roaming/VRCOSC" ]; then
            local username
            username="$(basename "$u")"
            mkdir -p "$stage_dir/users/${username}/AppData/Roaming"
            cp -a "$u/AppData/Roaming/VRCOSC" "$stage_dir/users/${username}/AppData/Roaming/"
            items_found=1
        fi
        if [ -d "$u/AppData/Roaming/VRCOSC-Beta" ]; then
            local username
            username="$(basename "$u")"
            mkdir -p "$stage_dir/users/${username}/AppData/Roaming"
            cp -a "$u/AppData/Roaming/VRCOSC-Beta" "$stage_dir/users/${username}/AppData/Roaming/"
            items_found=1
        fi
    done

    # Prune any broken or circular symbolic links to avoid compression errors
    find "$stage_dir" -xtype l -delete 2>/dev/null || true

    # 2. Wine prefix registry files
    for reg in "user.reg" "system.reg"; do
        if [ -f "$VRC_COMPATDATA/pfx/$reg" ]; then
            cp "$VRC_COMPATDATA/pfx/$reg" "$stage_dir/"
            items_found=1
        fi
    done

    # 3. Launchers & desktop shortcuts
    for f in "$HOME/.local/bin/vrcosc" "$HOME/.local/bin/vrcosc-beta" \
             "$HOME/.local/share/applications/vrcosc.desktop" "$HOME/.local/share/applications/vrcosc-beta.desktop"; do
        if [ -f "$f" ]; then
            mkdir -p "$stage_dir/launchers"
            cp "$f" "$stage_dir/launchers/"
            items_found=1
        fi
    done

    if [ "$items_found" -eq 0 ]; then
        log_warn "No VRCOSC configurations or registries found to backup."
        rm -rf "$stage_dir"
        return 0
    fi

    local archive_path=""
    if command -v 7z &>/dev/null; then
        archive_path="$desktop_dir/VRCOSC_backup_${timestamp}.7z"
        log_info "Compressing backup using 7z (LZMA2 ultra compression)..."
        7z a -t7z -m0=lzma2 -mx=9 -snl -bso0 -bsp0 "$archive_path" "$stage_dir"/*
    elif command -v tar &>/dev/null && command -v xz &>/dev/null; then
        archive_path="$desktop_dir/VRCOSC_backup_${timestamp}.tar.xz"
        log_info "Compressing backup using tar.xz (max compression)..."
        XZ_OPT="-9e" tar -cJf "$archive_path" -C "$stage_dir" .
    else
        archive_path="$desktop_dir/VRCOSC_backup_${timestamp}.tar.gz"
        log_info "Compressing backup using tar.gz..."
        tar -czf "$archive_path" -C "$stage_dir" .
    fi

    rm -rf "$stage_dir"
    log_success "Backup created successfully:"
    echo -e "  * ${CYAN}${archive_path}${NC}"
}

configure_protontricks_permissions() {
    if flatpak list 2>/dev/null | grep -q "protontricks"; then
        log_info "Updating flatpak sandbox permissions for protontricks..."
        if [ "$DRY_RUN" -eq 1 ]; then return 0; fi
        flatpak override --user --filesystem=host com.github.Matoking.protontricks || true
        flatpak override --user --talk-name=org.mpris.MediaPlayer2.* com.github.Matoking.protontricks || true
        flatpak override --user --talk-name=org.freedesktop.Flatpak com.github.Matoking.protontricks || true
    fi
}

apply_wpf_registry_fix() {
    log_info "Applying WPF hardware acceleration registry fix (prevents black window bug)..."
    if [ "$DRY_RUN" -eq 1 ]; then return 0; fi

    local reg_file="$VRC_COMPATDATA/pfx/drive_c/vrcosc_disable_hw_acc.reg"

    cat << 'EOF' > "$reg_file"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Microsoft\Avalon.Graphics]
"DisableHWAcceleration"=dword:00000001

[HKEY_LOCAL_MACHINE\Software\Microsoft\Avalon.Graphics]
"DisableHWAcceleration"=dword:00000001
EOF

    protontricks --no-bwrap -c "wine regedit C:\\vrcosc_disable_hw_acc.reg" 438100
    rm -f "$reg_file"
    log_success "WPF registry patch applied successfully."
}

install_dotnet_runtime() {
    local installed_dotnet="$VRC_COMPATDATA/pfx/drive_c/Program Files/dotnet/dotnet.exe"
    if [ -f "$installed_dotnet" ] && [ "$FORCE_INSTALL" -ne 1 ]; then
        log_success ".NET Runtime already present in prefix ($installed_dotnet). Skipping download (use -f/--force to reinstall)."
        return 0
    fi

    log_info "Fetching latest .NET 10.0 Desktop Runtime download URL..."
    local dotnet_url
    dotnet_url=$(curl -s https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/10.0/releases.json \
        | grep -o 'https://[^"]*windowsdesktop-runtime-[0-9.]*-win-x64.exe' | head -n 1)

    if [ -z "$dotnet_url" ]; then
        log_error "Error: Failed to fetch the .NET 10.0 Desktop Runtime download URL."
        exit 1
    fi

    log_info "Downloading .NET 10.0 from: $dotnet_url"
    local dotnet_installer="$VRC_COMPATDATA/pfx/drive_c/windowsdesktop-runtime-10.exe"
    if [ "$DRY_RUN" -eq 1 ]; then return 0; fi

    curl -L -o "$dotnet_installer" "$dotnet_url"

    log_info "Installing .NET 10.0 Desktop Runtime in VRChat prefix..."
    protontricks --no-bwrap -c "wine C:\\windowsdesktop-runtime-10.exe /quiet /norestart" 438100
    rm -f "$dotnet_installer"
    log_success ".NET 10.0 Desktop Runtime installed successfully."
}

install_vrcosc() {
    log_info "Fetching latest VRCOSC release version (channel: $VRCOSC_BRANCH)..."
    local latest_release_json nupkg_url
    latest_release_json=$(curl -s https://api.github.com/repos/VolcanicArts/VRCOSC/releases/latest)

    local pkg_pattern="live-full.nupkg"
    if [ "$VRCOSC_BRANCH" = "beta" ]; then
        pkg_pattern="beta-full.nupkg"
    fi

    nupkg_url=$(echo "$latest_release_json" | grep -o "https://github.com/VolcanicArts/VRCOSC/releases/download/[^\"]*${pkg_pattern}" | head -n 1)

    # Fallback to any full nupkg if channel-specific filename differs
    if [ -z "$nupkg_url" ]; then
        nupkg_url=$(echo "$latest_release_json" | grep -o 'https://github.com/VolcanicArts/VRCOSC/releases/download/[^"]*-full.nupkg' | head -n 1)
    fi

    if [ -z "$nupkg_url" ]; then
        log_error "Error: Failed to fetch the VRCOSC $VRCOSC_BRANCH package URL."
        exit 1
    fi

    log_info "Downloading VRCOSC package from: $nupkg_url"
    local nupkg_file="/tmp/vrcosc-latest.nupkg"
    if [ "$DRY_RUN" -eq 1 ]; then return 0; fi

    curl -L -o "$nupkg_file" "$nupkg_url"

    VRCOSC_DIR="$VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Local/VRCOSC"
    if [ "$VRCOSC_BRANCH" = "beta" ]; then
        VRCOSC_DIR="$VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Local/VRCOSC-beta"
    fi

    log_info "Installing VRCOSC to $VRCOSC_DIR..."
    mkdir -p "$VRCOSC_DIR"

    # Clean previous installation binaries
    rm -rf "${VRCOSC_DIR:?}"/*

    local temp_extract="/tmp/vrcosc-extract"
    rm -rf "$temp_extract"
    mkdir -p "$temp_extract"
    unzip -q "$nupkg_file" -d "$temp_extract"

    cp -r "$temp_extract/lib/app/"* "$VRCOSC_DIR/"
    rm -f "$nupkg_file"
    rm -rf "$temp_extract"
    log_success "VRCOSC files extracted successfully."
}

configure_firewall() {
    if [ "$SKIP_FIREWALL" -eq 1 ]; then
        log_info "Skipping firewall configuration (--skip-firewall)."
        return 0
    fi

    log_info "Checking firewall configuration for OSC and OSCQuery mDNS ports (9000/9001/5353 UDP)..."
    if [ "$DRY_RUN" -eq 1 ]; then return 0; fi

    local applied=0
    if command -v firewall-cmd &>/dev/null; then
        if sudo -n true 2>/dev/null; then
            log_info "Applying firewalld rules..."
            sudo -n firewall-cmd --add-port=9000/udp --permanent 2>/dev/null || true
            sudo -n firewall-cmd --add-port=9001/udp --permanent 2>/dev/null || true
            sudo -n firewall-cmd --add-port=5353/udp --permanent 2>/dev/null || true
            sudo -n firewall-cmd --reload 2>/dev/null || true
            applied=1
        fi
    elif command -v ufw &>/dev/null; then
        if sudo -n true 2>/dev/null; then
            log_info "Applying UFW rules..."
            sudo -n ufw allow 9000/udp 2>/dev/null || true
            sudo -n ufw allow 9001/udp 2>/dev/null || true
            sudo -n ufw allow 5353/udp 2>/dev/null || true
            sudo -n ufw reload 2>/dev/null || true
            applied=1
        fi
    elif command -v iptables &>/dev/null; then
        if sudo -n true 2>/dev/null; then
            log_info "Applying iptables rules..."
            sudo -n iptables -I INPUT -p udp --dport 9000 -j ACCEPT 2>/dev/null || true
            sudo -n iptables -I INPUT -p udp --dport 9001 -j ACCEPT 2>/dev/null || true
            sudo -n iptables -I INPUT -p udp --dport 5353 -j ACCEPT 2>/dev/null || true
            applied=1
        fi
    fi

    if [ "$applied" -eq 0 ]; then
        log_warn "Note: Automatic firewall rules were skipped (root privileges required)."
        echo -e "If VRChat fails to auto-discover VRCOSC, manually allow UDP ports 9000, 9001, and 5353 in your firewall."
    else
        log_success "Firewall rules configured successfully."
    fi
}

install_application_icon() {
    log_info "Installing VRCOSC application icon..."
    if [ "$DRY_RUN" -eq 1 ]; then return 0; fi

    local icon_dest_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
    mkdir -p "$icon_dest_dir"
    curl -sL -o "$icon_dest_dir/vrcosc.png" "$ICON_URL" || true
    if [ -f "$icon_dest_dir/vrcosc.png" ]; then
        log_success "Application icon installed: $icon_dest_dir/vrcosc.png"
    fi
}

create_launchers() {
    log_info "Creating launch script and desktop entry..."
    if [ "$DRY_RUN" -eq 1 ]; then return 0; fi

    local launch_script="$HOME/.local/bin/vrcosc"
    local win_entry="C:/users/steamuser/AppData/Local/VRCOSC/VRCOSC.dll"
    if [ "$VRCOSC_BRANCH" = "beta" ]; then
        launch_script="$HOME/.local/bin/vrcosc-beta"
        win_entry="C:/users/steamuser/AppData/Local/VRCOSC-beta/VRCOSC.dll"
    fi

    mkdir -p "$(dirname "$launch_script")"

    cat << EOF > "$launch_script"
#!/usr/bin/env bash
# VRCOSC Launcher for Linux/Proton
ENTRY="$win_entry"
DOTNET="C:/Program Files/dotnet/dotnet.exe"

exec protontricks --no-bwrap -c "wine \\"\$DOTNET\\" \\"\$ENTRY\\" \$*" 438100
EOF
    chmod +x "$launch_script"

    local desktop_entry="$HOME/.local/share/applications/vrcosc.desktop"
    local app_name="VRCOSC"
    if [ "$VRCOSC_BRANCH" = "beta" ]; then
        desktop_entry="$HOME/.local/share/applications/vrcosc-beta.desktop"
        app_name="VRCOSC (Beta)"
    fi

    mkdir -p "$(dirname "$desktop_entry")"

    cat << EOF > "$desktop_entry"
[Desktop Entry]
Name=$app_name
Comment=OSC controller for VRChat
Exec=$launch_script
Icon=vrcosc
Terminal=false
Type=Application
Categories=Game;Utility;
StartupWMClass=VRCOSC
EOF

    log_success "=== VRCOSC Setup Complete! ==="
    echo -e "You can launch VRCOSC from your application menu, or run '${BLUE}$(basename "$launch_script")${NC}' in the terminal."
    echo -e "\n${BLUE}VRCOSC Directory Paths:${NC}"
    echo -e "  * ${GREEN}Config Folder (Profiles & Settings):${NC}"
    echo -e "    $VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Roaming/VRCOSC"
    echo -e "  * ${GREEN}Executable Folder (App Files):${NC}"
    echo -e "    $VRCOSC_DIR"
}

uninstall_vrcosc() {
    log_warn "Starting VRCOSC uninstallation..."
    locate_vrchat_prefix

    local removed=0
    # Remove installation directories
    for dir in "$VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Local/VRCOSC" \
               "$VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Local/VRCOSC-beta"; do
        if [ -d "$dir" ]; then
            log_info "Removing binaries: $dir"
            rm -rf "$dir"
            removed=1
        fi
    done

    # Remove launchers
    for f in "$HOME/.local/bin/vrcosc" "$HOME/.local/bin/vrcosc-beta" \
             "$HOME/.local/share/applications/vrcosc.desktop" "$HOME/.local/share/applications/vrcosc-beta.desktop" \
             "$HOME/.local/share/icons/hicolor/256x256/apps/vrcosc.png"; do
        if [ -f "$f" ]; then
            log_info "Removing file: $f"
            rm -f "$f"
            removed=1
        fi
    done

    if [ "$removed" -eq 1 ]; then
        log_success "VRCOSC successfully uninstalled."
        echo -e "${YELLOW}Note: Your configurations in AppData/Roaming/VRCOSC have been preserved.${NC}"
    else
        log_info "Nothing found to uninstall."
    fi
}

main() {
    parse_arguments "$@"

    if [ "$BACKUP_MODE" -eq 1 ]; then
        create_backup
        exit 0
    fi

    if [ "$UNINSTALL_MODE" -eq 1 ]; then
        uninstall_vrcosc
        exit 0
    fi

    echo -e "${BLUE}=== VRCOSC Bazzite/Linux Installer ===${NC}"
    check_dependencies
    locate_vrchat_prefix
    configure_protontricks_permissions
    apply_wpf_registry_fix
    install_dotnet_runtime
    install_vrcosc
    configure_firewall
    install_application_icon
    create_launchers
}

main "$@"
