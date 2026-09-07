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
INFO_MODE=0
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

# --- Path & Integration Helper Functions ---
get_launcher_script() {
    [ "${1:-$VRCOSC_BRANCH}" = "beta" ] && echo "$HOME/.local/bin/vrcosc-beta" || echo "$HOME/.local/bin/vrcosc"
}

get_desktop_file() {
    [ "${1:-$VRCOSC_BRANCH}" = "beta" ] && echo "$HOME/.local/share/applications/vrcosc-beta.desktop" || echo "$HOME/.local/share/applications/vrcosc.desktop"
}

get_app_icon_path() {
    echo "$HOME/.local/share/icons/hicolor/256x256/apps/vrcosc.png"
}

get_vrcosc_install_dir() {
    local base="$VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Local"
    [ "${1:-$VRCOSC_BRANCH}" = "beta" ] && echo "$base/VRCOSC-beta" || echo "$base/VRCOSC"
}

get_vrchat_game_dir() {
    local steamapps_dir="$(dirname "$(dirname "$VRC_COMPATDATA")")"
    echo "$steamapps_dir/common/VRChat"
}

get_all_installed_files() {
    echo "$(get_launcher_script live)" \
         "$(get_launcher_script beta)" \
         "$(get_desktop_file live)" \
         "$(get_desktop_file beta)" \
         "$(get_app_icon_path)"
}

get_vrcosc_version_from_dir() {
    local dir="$1"
    local deps="$dir/VRCOSC.deps.json"
    local dll="$dir/VRCOSC.dll"
    if [ -f "$deps" ]; then
        local v
        v="$(grep -o '"VRCOSC.App": "[^"]*"' "$deps" 2>/dev/null | head -n 1 | cut -d'"' -f4 || true)"
        [ -n "$v" ] && echo "$v" && return 0
    fi
    [ -f "$dll" ] && echo "Installed" && return 0
    echo "Not installed"
}

print_usage() {
    echo -e "${BOLD}VRCOSC Linux Installer & Manager${NC}"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  bash install.sh [OPTIONS]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  -i, --info                Display diagnostic system, prefix, runtime, and VRCOSC environment info"
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
            -i|--info)
                INFO_MODE=1
                shift
                ;;
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

find_prefix_silently() {
    if [ -n "$VRC_COMPATDATA" ]; then
        VRC_COMPATDATA="${VRC_COMPATDATA/#\~/$HOME}"
        if [ -d "$VRC_COMPATDATA/pfx" ]; then
            return 0
        elif [ -d "$VRC_COMPATDATA/compatdata/438100/pfx" ]; then
            VRC_COMPATDATA="$VRC_COMPATDATA/compatdata/438100"
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

    for p in "${candidate_paths[@]}"; do
        for check_dir in "$p" "$p/steamapps"; do
            if [ -d "$check_dir/compatdata/438100/pfx" ]; then
                VRC_COMPATDATA="$check_dir/compatdata/438100"
                return 0
            fi
        done
    done
    return 1
}

locate_vrchat_prefix() {
    log_info "Locating VRChat Proton prefix..."

    if find_prefix_silently; then
        log_success "Found VRChat compatibility data at: $VRC_COMPATDATA"
        return 0
    fi

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

show_diagnostics() {
    log_info "Collecting diagnostic and environment information..."
    echo ""

    # System & OS Information
    echo -e "${BOLD}=== System & OS Environment ===${NC}"
    local os_pretty="Unknown"
    [ -f /etc/os-release ] && os_pretty="$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2- | tr -d '"')"
    local kernel_ver="$(uname -r 2>/dev/null || echo 'Unknown')"
    local arch="$(uname -m 2>/dev/null || echo 'Unknown')"
    local de="${XDG_CURRENT_DESKTOP:-Unknown}"
    local session_type="${XDG_SESSION_TYPE:-Unknown}"
    local desktop_session="${DESKTOP_SESSION:-Unknown}"

    echo -e "  * OS:                    ${CYAN}${os_pretty}${NC}"
    echo -e "  * Kernel:                ${CYAN}${kernel_ver} (${arch})${NC}"
    echo -e "  * Desktop Environment:   ${CYAN}${de} (${session_type})${NC}"
    echo -e "  * Session:               ${CYAN}${desktop_session}${NC}"

    # Tooling
    echo ""
    echo -e "${BOLD}=== Tooling & Runtime Dependencies ===${NC}"
    local pt_ver="Not installed"
    command -v protontricks &>/dev/null && pt_ver="$(protontricks --version 2>&1 | head -n 1)"
    local curl_ver="Not installed"
    command -v curl &>/dev/null && curl_ver="$(curl --version 2>&1 | head -n 1 | awk '{print $1, $2}')"
    local unzip_ver="Not installed"
    command -v unzip &>/dev/null && unzip_ver="Installed ($(which unzip))"
    local archiver="tar/xz"
    if command -v 7z &>/dev/null; then
        local z7_ver="$(7z 2>&1 | grep -i '7-Zip' | head -n 1 | awk '{print $2}')"
        archiver="7z (${z7_ver:-installed})"
    fi

    echo -e "  * Protontricks:          ${CYAN}${pt_ver}${NC}"
    echo -e "  * cURL:                  ${CYAN}${curl_ver}${NC}"
    echo -e "  * Unzip:                 ${CYAN}${unzip_ver}${NC}"
    echo -e "  * Compression Tool:      ${CYAN}${archiver}${NC}"

    # Prefix & Wine Configuration
    echo ""
    echo -e "${BOLD}=== VRChat Proton Prefix ===${NC}"
    find_prefix_silently || true

    if [ -n "$VRC_COMPATDATA" ] && [ -d "$VRC_COMPATDATA/pfx" ]; then
        echo -e "  * Prefix Root:           ${CYAN}${VRC_COMPATDATA}${NC}"
        echo -e "  * Prefix pfx:            ${CYAN}${VRC_COMPATDATA}/pfx${NC}"

        local user_reg_status="Missing"
        [ -f "$VRC_COMPATDATA/pfx/user.reg" ] && user_reg_status="Present"
        local sys_reg_status="Missing"
        [ -f "$VRC_COMPATDATA/pfx/system.reg" ] && sys_reg_status="Present"

        echo -e "  * Registry (user.reg):   ${CYAN}${VRC_COMPATDATA}/pfx/user.reg${NC} (${user_reg_status})"
        echo -e "  * Registry (system.reg): ${CYAN}${VRC_COMPATDATA}/pfx/system.reg${NC} (${sys_reg_status})"

        local wpf_disabled=0
        if [ -f "$VRC_COMPATDATA/pfx/user.reg" ] && grep -q 'DisableHWAcceleration' "$VRC_COMPATDATA/pfx/user.reg"; then
            wpf_disabled=1
        elif [ -f "$VRC_COMPATDATA/pfx/system.reg" ] && grep -q 'DisableHWAcceleration' "$VRC_COMPATDATA/pfx/system.reg"; then
            wpf_disabled=1
        fi
        if [ "$wpf_disabled" -eq 1 ]; then
            echo -e "  * WPF HW Accel Patch:    ${GREEN}Applied (DisableHWAcceleration=1)${NC}"
        else
            echo -e "  * WPF HW Accel Patch:    ${YELLOW}Not detected (Black window issue may occur)${NC}"
        fi

        local dotnet_exe="$VRC_COMPATDATA/pfx/drive_c/Program Files/dotnet/dotnet.exe"
        local dotnet_status="Not installed"
        [ -f "$dotnet_exe" ] && dotnet_status="Installed ($dotnet_exe)"
        echo -e "  * .NET Binary:           ${CYAN}${dotnet_status}${NC}"

        local desktop_runtimes=()
        local shared_dir="$VRC_COMPATDATA/pfx/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App"
        if [ -d "$shared_dir" ]; then
            for d in "$shared_dir/"*; do
                [ -d "$d" ] && desktop_runtimes+=("$(basename "$d")")
            done
        fi
        if [ ${#desktop_runtimes[@]} -gt 0 ]; then
            echo -e "  * .NET WindowsDesktop:   ${CYAN}${desktop_runtimes[*]}${NC}"
        else
            echo -e "  * .NET WindowsDesktop:   ${YELLOW}None detected${NC}"
        fi

        echo ""
        echo -e "${BOLD}=== VRCOSC User Config Directories ===${NC}"
        local cfgs_found=0
        for u in "$VRC_COMPATDATA/pfx/drive_c/users/"*; do
            local uname="$(basename "$u")"
            for ch in "VRCOSC:Live" "VRCOSC-Beta:Beta"; do
                local folder="${ch%%:*}"
                local label="${ch##*:}"
                local cfg_dir="$u/AppData/Roaming/$folder"
                if [ -d "$cfg_dir" ]; then
                    local real_tgt=""
                    [ -L "$cfg_dir" ] && real_tgt=" -> $(readlink "$cfg_dir")"
                    echo -e "  * User [${uname}] (${label}):     ${CYAN}${cfg_dir}${NC}${real_tgt}"
                    cfgs_found=1
                fi
            done
        done
        [ "$cfgs_found" -eq 0 ] && echo -e "  * ${YELLOW}No active VRCOSC AppData config directories found.${NC}"

        echo ""
        echo -e "${BOLD}=== VRCOSC Installation & Versions ===${NC}"
        echo -e "  * Local Version (Live):   ${CYAN}$(get_vrcosc_version_from_dir "$(get_vrcosc_install_dir live)")${NC}"
        echo -e "  * Local Version (Beta):   ${CYAN}$(get_vrcosc_version_from_dir "$(get_vrcosc_install_dir beta)")${NC}"
    else
        echo -e "  * Prefix Root:           ${YELLOW}Not detected (use --prefix <PATH> if located on an external drive)${NC}"
    fi

    # Remote GitHub Releases
    local remote_live="Unavailable (Network/Rate-limited)"
    local remote_beta="Unavailable (Network/Rate-limited)"
    local releases_json
    releases_json="$(curl -s --connect-timeout 4 -H "User-Agent: vrcosc-installer" https://api.github.com/repos/VolcanicArts/VRCOSC/releases 2>/dev/null || true)"
    if [ -n "$releases_json" ]; then
        if command -v python3 &>/dev/null; then
            remote_live="$(python3 -c "import json,sys; data=json.loads(sys.stdin.read()); print(next((r['tag_name'] for r in data if not r.get('prerelease')), 'Unavailable'))" <<< "$releases_json" 2>/dev/null || echo 'Unavailable')"
            remote_beta="$(python3 -c "import json,sys; data=json.loads(sys.stdin.read()); print(next((r['tag_name'] for r in data if r.get('prerelease')), 'Unavailable'))" <<< "$releases_json" 2>/dev/null || echo 'Unavailable')"
        else
            remote_live="$(echo "$releases_json" | grep -B 10 -A 2 '"prerelease": false' | grep '"tag_name":' | head -n 1 | cut -d'"' -f4 || echo 'Unavailable')"
            remote_beta="$(echo "$releases_json" | grep -B 10 -A 2 '"prerelease": true' | grep '"tag_name":' | head -n 1 | cut -d'"' -f4 || echo 'Unavailable')"
        fi
    fi
    echo -e "  * Remote Latest (Live):   ${CYAN}${remote_live}${NC}"
    echo -e "  * Remote Latest (Beta):   ${CYAN}${remote_beta}${NC}"

    echo ""
    echo -e "${BOLD}=== Integration & Launchers ===${NC}"
    local v_live="$(get_launcher_script live)"
    local v_beta="$(get_launcher_script beta)"
    local d_live="$(get_desktop_file live)"
    local d_beta="$(get_desktop_file beta)"
    local icon_path="$(get_app_icon_path)"

    echo -e "  * Command (vrcosc):        $([ -f "$v_live" ] && echo -e "${CYAN}Installed ($v_live)${NC}" || echo -e "${YELLOW}Missing${NC}")"
    echo -e "  * Command (vrcosc-beta):   $([ -f "$v_beta" ] && echo -e "${CYAN}Installed ($v_beta)${NC}" || echo -e "${YELLOW}Missing${NC}")"
    echo -e "  * Desktop (Live):          $([ -f "$d_live" ] && echo -e "${CYAN}Present ($d_live)${NC}" || echo -e "${YELLOW}Missing${NC}")"
    echo -e "  * Desktop (Beta):          $([ -f "$d_beta" ] && echo -e "${CYAN}Present ($d_beta)${NC}" || echo -e "${YELLOW}Missing${NC}")"
    echo -e "  * Icon:                    $([ -f "$icon_path" ] && echo -e "${CYAN}Present ($icon_path)${NC}" || echo -e "${YELLOW}Missing${NC}")"

    local vrc_game_dir="$(get_vrchat_game_dir)"
    local target_launch="$vrc_game_dir/launch.exe"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local source_bridge="$script_dir/bin/vrc-launch-bridge.exe"
    local bridge_status="${YELLOW}Unpatched / Missing${NC}"
    if [ -f "$target_launch" ] && [ -f "$source_bridge" ] && cmp -s "$source_bridge" "$target_launch"; then
        bridge_status="${GREEN}Patched (Linux IPC Named-Pipe Bridge)${NC}"
    elif [ -f "$target_launch" ]; then
        bridge_status="${YELLOW}Stock launch.exe (Unpatched)${NC}"
    fi
    echo -e "  * VRChat Launch Bridge:    ${bridge_status}"

    echo ""
    echo -e "${BOLD}=== Community & Support ===${NC}"
    echo -e "  * Server Invite:           ${CYAN}${DISCORD_INVITE}${NC}"
    echo -e "  * Linux Discussion:        ${CYAN}${DISCORD_THREAD}${NC}"
    echo ""
}

create_backup() {
    log_info "Initiating VRCOSC and prefix backup..."
    locate_vrchat_prefix

    local desktop_dir
    desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
    mkdir -p "$desktop_dir"

    local timestamp="$(date +%s)"
    local stage_dir="/tmp/vrcosc_backup_${timestamp}"
    mkdir -p "$stage_dir"

    local items_found=0

    # 1. Config directories (Roaming/VRCOSC, Roaming/VRCOSC-Beta)
    for u in "$VRC_COMPATDATA/pfx/drive_c/users/"*; do
        local username="$(basename "$u")"
        for folder in "VRCOSC" "VRCOSC-Beta"; do
            if [ -d "$u/AppData/Roaming/$folder" ]; then
                mkdir -p "$stage_dir/users/${username}/AppData/Roaming"
                cp -a "$u/AppData/Roaming/$folder" "$stage_dir/users/${username}/AppData/Roaming/"
                items_found=1
            fi
        done
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
    for f in $(get_all_installed_files); do
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
        [ "$DRY_RUN" -eq 1 ] && return 0
        flatpak override --user --filesystem=host com.github.Matoking.protontricks || true
        flatpak override --user --talk-name=org.mpris.MediaPlayer2.* com.github.Matoking.protontricks || true
        flatpak override --user --talk-name=org.freedesktop.Flatpak com.github.Matoking.protontricks || true
    fi
}

apply_wpf_registry_fix() {
    log_info "Applying WPF hardware acceleration registry fix (prevents black window bug)..."
    [ "$DRY_RUN" -eq 1 ] && return 0

    local reg_file="$VRC_COMPATDATA/pfx/drive_c/vrcosc_disable_hw_acc.reg"

    cat << 'EOF_REG' > "$reg_file"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Microsoft\Avalon.Graphics]
"DisableHWAcceleration"=dword:00000001

[HKEY_LOCAL_MACHINE\Software\Microsoft\Avalon.Graphics]
"DisableHWAcceleration"=dword:00000001
EOF_REG

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
    [ "$DRY_RUN" -eq 1 ] && return 0

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
    [ "$VRCOSC_BRANCH" = "beta" ] && pkg_pattern="beta-full.nupkg"

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
    [ "$DRY_RUN" -eq 1 ] && return 0

    curl -L -o "$nupkg_file" "$nupkg_url"

    local vrcosc_dir="$(get_vrcosc_install_dir)"
    log_info "Installing VRCOSC to $vrcosc_dir..."
    mkdir -p "$vrcosc_dir"

    # Clean previous installation binaries
    rm -rf "${vrcosc_dir:?}"/*

    local temp_extract="/tmp/vrcosc-extract"
    rm -rf "$temp_extract"
    mkdir -p "$temp_extract"
    unzip -q "$nupkg_file" -d "$temp_extract"

    cp -r "$temp_extract/lib/app/"* "$vrcosc_dir/"
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
    [ "$DRY_RUN" -eq 1 ] && return 0

    local applied=0
    if command -v firewall-cmd &>/dev/null && sudo -n true 2>/dev/null; then
        log_info "Applying firewalld rules..."
        sudo -n firewall-cmd --add-port=9000/udp --permanent 2>/dev/null || true
        sudo -n firewall-cmd --add-port=9001/udp --permanent 2>/dev/null || true
        sudo -n firewall-cmd --add-port=5353/udp --permanent 2>/dev/null || true
        sudo -n firewall-cmd --reload 2>/dev/null || true
        applied=1
    elif command -v ufw &>/dev/null && sudo -n true 2>/dev/null; then
        log_info "Applying UFW rules..."
        sudo -n ufw allow 9000/udp 2>/dev/null || true
        sudo -n ufw allow 9001/udp 2>/dev/null || true
        sudo -n ufw allow 5353/udp 2>/dev/null || true
        sudo -n ufw reload 2>/dev/null || true
        applied=1
    elif command -v iptables &>/dev/null && sudo -n true 2>/dev/null; then
        log_info "Applying iptables rules..."
        sudo -n iptables -I INPUT -p udp --dport 9000 -j ACCEPT 2>/dev/null || true
        sudo -n iptables -I INPUT -p udp --dport 9001 -j ACCEPT 2>/dev/null || true
        sudo -n iptables -I INPUT -p udp --dport 5353 -j ACCEPT 2>/dev/null || true
        applied=1
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
    [ "$DRY_RUN" -eq 1 ] && return 0

    local icon_path="$(get_app_icon_path)"
    mkdir -p "$(dirname "$icon_path")"
    curl -sL -o "$icon_path" "$ICON_URL" || true
    if [ -f "$icon_path" ]; then
        log_success "Application icon installed: $icon_path"
    fi
}

patch_vrchat_launch_bridge() {
    log_info "Checking VRChat launch.exe for Linux IPC named-pipe bridge patch..."
    [ "$DRY_RUN" -eq 1 ] && return 0

    local vrc_game_dir="$(get_vrchat_game_dir)"
    local target_launch="$vrc_game_dir/launch.exe"
    local backup_launch="$vrc_game_dir/launch.org.exe"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local source_bridge="$script_dir/bin/vrc-launch-bridge.exe"

    if [ ! -d "$vrc_game_dir" ]; then
        log_warn "VRChat game directory not found ($vrc_game_dir). Skipping launch.exe patch."
        return 0
    fi

    if [ ! -f "$source_bridge" ]; then
        log_warn "vrc-launch-bridge.exe not found at $source_bridge. Skipping patch."
        return 0
    fi

    # Backup original launch.exe if launch.org.exe does not exist
    if [ ! -f "$backup_launch" ]; then
        if [ -f "$target_launch" ]; then
            log_info "Creating read-only backup of original launch.exe -> launch.org.exe..."
            cp -p "$target_launch" "$backup_launch"
            chmod 444 "$backup_launch"
        fi
    fi

    # Compare checksum or size to see if already patched
    if [ -f "$target_launch" ] && cmp -s "$source_bridge" "$target_launch"; then
        log_success "VRChat launch.exe is already patched with the Linux IPC bridge."
        chmod 555 "$target_launch" 2>/dev/null || true
        return 0
    fi

    log_info "Installing Linux IPC launch.exe wrapper into VRChat directory..."
    # If target is read-only, remove write protection temporarily to replace
    rm -f "$target_launch" 2>/dev/null || chmod 755 "$target_launch" 2>/dev/null || true
    cp "$source_bridge" "$target_launch"
    chmod 555 "$target_launch"
    log_success "VRChat launch.exe patched successfully (read-only 555)."
}

create_launchers() {
    log_info "Creating launch script and desktop entry..."
    [ "$DRY_RUN" -eq 1 ] && return 0

    local launch_script="$(get_launcher_script)"
    local win_entry="C:/users/steamuser/AppData/Local/VRCOSC/VRCOSC.dll"
    local desktop_entry="$(get_desktop_file)"
    local app_name="VRCOSC"

    if [ "$VRCOSC_BRANCH" = "beta" ]; then
        win_entry="C:/users/steamuser/AppData/Local/VRCOSC-beta/VRCOSC.dll"
        app_name="VRCOSC (Beta)"
    fi

    mkdir -p "$(dirname "$launch_script")"
    cat << EOF_LAUNCHER > "$launch_script"
#!/usr/bin/env bash
# VRCOSC Launcher for Linux/Proton
ENTRY="$win_entry"
DOTNET="C:/Program Files/dotnet/dotnet.exe"

exec protontricks --no-bwrap -c "wine \\"\$DOTNET\\" \\"\$ENTRY\\" \$*" 438100
EOF_LAUNCHER
    chmod +x "$launch_script"

    mkdir -p "$(dirname "$desktop_entry")"
    cat << EOF_DESKTOP > "$desktop_entry"
[Desktop Entry]
Name=$app_name
Comment=OSC controller for VRChat
Exec=$launch_script
Icon=vrcosc
Terminal=false
Type=Application
Categories=Game;Utility;
StartupWMClass=VRCOSC
EOF_DESKTOP

    local vrcosc_dir="$(get_vrcosc_install_dir)"
    log_success "=== VRCOSC Setup Complete! ==="
    echo -e "You can launch VRCOSC from your application menu, or run '${BLUE}$(basename "$launch_script")${NC}' in the terminal."
    echo -e "\n${BLUE}VRCOSC Directory Paths:${NC}"
    echo -e "  * ${GREEN}Config Folder (Profiles & Settings):${NC}"
    echo -e "    $VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Roaming/VRCOSC"
    echo -e "  * ${GREEN}Executable Folder (App Files):${NC}"
    echo -e "    $vrcosc_dir"
}

uninstall_vrcosc() {
    log_warn "Starting VRCOSC uninstallation..."
    locate_vrchat_prefix

    local removed=0
    # Remove installation directories
    for dir in "$(get_vrcosc_install_dir live)" "$(get_vrcosc_install_dir beta)"; do
        if [ -d "$dir" ]; then
            log_info "Removing binaries: $dir"
            rm -rf "$dir"
            removed=1
        fi
    done

    # Remove launchers, shortcuts, and icon
    for f in $(get_all_installed_files); do
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

    if [ "$INFO_MODE" -eq 1 ]; then
        show_diagnostics
        exit 0
    fi

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
    patch_vrchat_launch_bridge
    create_launchers
}

main "$@"
