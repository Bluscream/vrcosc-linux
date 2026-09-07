#!/usr/bin/env bash

# VRCOSC automated installer and runner setup script for Bazzite / Linux
set -euo pipefail

# Visual styling
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0;0m' # No Color

log_info()    { echo -e "${BLUE}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_warn()    { echo -e "${YELLOW}$*${NC}"; }
log_error()   { echo -e "${RED}$*${NC}"; }

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
    VRC_COMPATDATA="${VRC_COMPATDATA:-}"

    if [ -n "$VRC_COMPATDATA" ] && [ -d "$VRC_COMPATDATA/pfx" ]; then
        log_success "Using pre-configured VRChat prefix: $VRC_COMPATDATA"
        return 0
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
        echo "Set VRC_COMPATDATA=/path/to/compatdata/438100 or run interactively in a terminal."
        exit 1
    fi
}

configure_protontricks_permissions() {
    if flatpak list 2>/dev/null | grep -q "protontricks"; then
        log_info "Updating flatpak permissions for protontricks..."
        flatpak override --user --filesystem=host com.github.Matoking.protontricks || true
        flatpak override --user --talk-name=org.mpris.MediaPlayer2.* com.github.Matoking.protontricks || true
        flatpak override --user --talk-name=org.freedesktop.Flatpak com.github.Matoking.protontricks || true
    fi
}

apply_wpf_registry_fix() {
    log_info "Applying WPF hardware acceleration registry fix (fixes black window bug)..."
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
    curl -L -o "$dotnet_installer" "$dotnet_url"

    log_info "Installing .NET 10.0 Desktop Runtime in VRChat prefix..."
    protontricks --no-bwrap -c "wine C:\\windowsdesktop-runtime-10.exe /quiet /norestart" 438100
    rm -f "$dotnet_installer"
    log_success ".NET 10.0 Desktop Runtime installed successfully."
}

install_vrcosc() {
    log_info "Fetching latest VRCOSC release version..."
    local latest_release_json nupkg_url
    latest_release_json=$(curl -s https://api.github.com/repos/VolcanicArts/VRCOSC/releases/latest)
    nupkg_url=$(echo "$latest_release_json" | grep -o 'https://github.com/VolcanicArts/VRCOSC/releases/download/[^"]*live-full.nupkg' | head -n 1)

    if [ -z "$nupkg_url" ]; then
        log_error "Error: Failed to fetch the VRCOSC live package URL."
        exit 1
    fi

    log_info "Downloading VRCOSC package from: $nupkg_url"
    local nupkg_file="/tmp/vrcosc-latest.nupkg"
    curl -L -o "$nupkg_file" "$nupkg_url"

    VRCOSC_DIR="$VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Local/VRCOSC"
    log_info "Installing VRCOSC to $VRCOSC_DIR..."
    mkdir -p "$VRCOSC_DIR"

    # Clean old binaries
    rm -rf "$VRCOSC_DIR"/*

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
    log_info "Configuring firewall for OSC and OSCQuery mDNS ports (9000/9001/5353 UDP)..."
    if command -v firewall-cmd &>/dev/null; then
        log_info "Using firewalld to open ports..."
        sudo -n firewall-cmd --add-port=9000/udp --permanent 2>/dev/null || true
        sudo -n firewall-cmd --add-port=9001/udp --permanent 2>/dev/null || true
        sudo -n firewall-cmd --add-port=5353/udp --permanent 2>/dev/null || true
        sudo -n firewall-cmd --reload 2>/dev/null || true
    elif command -v ufw &>/dev/null; then
        log_info "Using UFW to open ports..."
        sudo -n ufw allow 9000/udp 2>/dev/null || true
        sudo -n ufw allow 9001/udp 2>/dev/null || true
        sudo -n ufw allow 5353/udp 2>/dev/null || true
        sudo -n ufw reload 2>/dev/null || true
    elif command -v iptables &>/dev/null; then
        log_info "Using iptables to open ports..."
        sudo -n iptables -I INPUT -p udp --dport 9000 -j ACCEPT 2>/dev/null || true
        sudo -n iptables -I INPUT -p udp --dport 9001 -j ACCEPT 2>/dev/null || true
        sudo -n iptables -I INPUT -p udp --dport 5353 -j ACCEPT 2>/dev/null || true
    else
        echo "No supported firewall manager found or sudo required. Ensure UDP ports 9000, 9001, and 5353 are allowed."
    fi
}

create_launchers() {
    log_info "Creating launch script and desktop entry..."
    local launch_script="$HOME/.local/bin/vrcosc"
    mkdir -p "$(dirname "$launch_script")"

    cat << 'EOF' > "$launch_script"
#!/usr/bin/env bash
# VRCOSC Launcher for Linux/Proton
ENTRY="C:/users/steamuser/AppData/Local/VRCOSC/VRCOSC.dll"
DOTNET="C:/Program Files/dotnet/dotnet.exe"

exec protontricks --no-bwrap -c "wine \"$DOTNET\" \"$ENTRY\" $*" 438100
EOF
    chmod +x "$launch_script"

    local desktop_entry="$HOME/.local/share/applications/vrcosc.desktop"
    mkdir -p "$(dirname "$desktop_entry")"

    cat << EOF > "$desktop_entry"
[Desktop Entry]
Name=VRCOSC
Comment=OSC controller for VRChat
Exec=$launch_script
Icon=steam
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=VRCOSC
EOF

    log_success "=== VRCOSC Setup Complete! ==="
    echo -e "You can launch VRCOSC from your application menu, or run '${BLUE}vrcosc${NC}' in the terminal."
    echo -e "\n${BLUE}VRCOSC Directory Paths:${NC}"
    echo -e "  * ${GREEN}Config Folder (Profiles & Settings):${NC}"
    echo -e "    $VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Roaming/VRCOSC"
    echo -e "  * ${GREEN}Executable Folder (App Files):${NC}"
    echo -e "    $VRCOSC_DIR"
}

main() {
    echo -e "${BLUE}=== VRCOSC Bazzite/Linux Installer ===${NC}"
    check_dependencies
    locate_vrchat_prefix
    configure_protontricks_permissions
    apply_wpf_registry_fix
    install_dotnet_runtime
    install_vrcosc
    configure_firewall
    create_launchers
}

main "$@"
