#!/usr/bin/env bash

# VRCOSC automated installer and runner setup script for Bazzite / Linux
set -euo pipefail

# Visual styling
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0;0m' # No Color

echo -e "${BLUE}=== VRCOSC Bazzite/Linux Installer ===${NC}"

# 1. Verify dependencies
if ! command -v protontricks &> /dev/null; then
    echo -e "${RED}Error: protontricks is not installed. Please install it first.${NC}"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is required but not installed.${NC}"
    exit 1
fi

if ! command -v unzip &> /dev/null; then
    echo -e "${RED}Error: unzip is required but not installed.${NC}"
    exit 1
fi

# 2. Locate VRChat prefix
echo -e "${BLUE}Locating VRChat prefix...${NC}"
VRC_COMPATDATA=""

# Assemble search candidates: standard Steam locations + dynamically parsed libraryfolders.vdf
CANDIDATE_PATHS=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.steam/steam"
    "/run/media/system/Data/Games/Steam"
    "/media/media-automount/Data/Games/Steam"
)

# Parse all accessible libraryfolders.vdf files to discover secondary/external drives automatically
for vdf in "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" \
           "$HOME/.steam/steam/steamapps/libraryfolders.vdf" \
           "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf"; do
    if [ -f "$vdf" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ \"path\"[[:space:]]*\"([^\"]+)\" ]]; then
                CANDIDATE_PATHS+=("${BASH_REMATCH[1]}")
            fi
        done < "$vdf"
    fi
done

# Search for the VRChat Proton prefix (app ID 438100)
for p in "${CANDIDATE_PATHS[@]}"; do
    # Check both direct directory and steamapps subdirectories
    for check_dir in "$p" "$p/steamapps"; do
        if [ -d "$check_dir/compatdata/438100/pfx" ]; then
            VRC_COMPATDATA="$check_dir/compatdata/438100"
            echo -e "${GREEN}Found VRChat compatibility data at: $VRC_COMPATDATA${NC}"
            break 2
        fi
    done
done

# If autodetect fails, prompt user interactively or check for custom environment variable
if [ -z "$VRC_COMPATDATA" ]; then
    echo -e "${YELLOW}Could not automatically locate the VRChat (438100) Proton prefix.${NC}"
    
    if [ -t 0 ]; then
        while [ -z "$VRC_COMPATDATA" ]; do
            echo -e "${BLUE}Please enter the path to your SteamLibrary or the 438100 compatdata folder:${NC}"
            read -r -p "Path: " user_path
            user_path="${user_path/#\~/$HOME}"
            
            if [ -d "$user_path/pfx" ] && [[ "$user_path" == *"438100"* ]]; then
                VRC_COMPATDATA="$user_path"
            elif [ -d "$user_path/compatdata/438100/pfx" ]; then
                VRC_COMPATDATA="$user_path/compatdata/438100"
            elif [ -d "$user_path/steamapps/compatdata/438100/pfx" ]; then
                VRC_COMPATDATA="$user_path/steamapps/compatdata/438100"
            else
                echo -e "${RED}Invalid path. Could not find 'pfx' folder for app 438100 under '$user_path'. Please try again.${NC}"
            fi
        done
        echo -e "${GREEN}Using VRChat prefix at: $VRC_COMPATDATA${NC}"
    else
        echo -e "${RED}Error: Running non-interactively and prefix was not found.${NC}"
        echo "Set VRC_COMPATDATA=/path/to/compatdata/438100 or run interactively in a terminal."
        exit 1
    fi
fi

# Ensure flatpak protontricks has access to the steam directories if running under flatpak
if flatpak list 2>/dev/null | grep -q "protontricks"; then
    echo -e "${BLUE}Updating flatpak permissions for protontricks...${NC}"
    flatpak override --user --filesystem=host com.github.Matoking.protontricks || true
    flatpak override --user --talk-name=org.mpris.MediaPlayer2.* com.github.Matoking.protontricks || true
    flatpak override --user --talk-name=org.freedesktop.Flatpak com.github.Matoking.protontricks || true
fi

# 3. Apply WPF Hardware Acceleration Fix
echo -e "${BLUE}Applying WPF hardware acceleration registry fix (fixes black window bug)...${NC}"
REG_FILE="$VRC_COMPATDATA/pfx/drive_c/vrcosc_disable_hw_acc.reg"
cat << 'EOF' > "$REG_FILE"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Microsoft\Avalon.Graphics]
"DisableHWAcceleration"=dword:00000001

[HKEY_LOCAL_MACHINE\Software\Microsoft\Avalon.Graphics]
"DisableHWAcceleration"=dword:00000001
EOF

protontricks --no-bwrap -c "wine regedit C:\\vrcosc_disable_hw_acc.reg" 438100
echo -e "${GREEN}WPF registry patch applied successfully.${NC}"

# 4. Download and Install .NET 10 Desktop Runtime
echo -e "${BLUE}Fetching latest .NET 10.0 Desktop Runtime download URL...${NC}"
DOTNET_URL=$(curl -s https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/10.0/releases.json | grep -o 'https://[^"]*windowsdesktop-runtime-[0-9.]*-win-x64.exe' | head -n 1)

if [ -z "$DOTNET_URL" ]; then
    echo -e "${RED}Error: Failed to fetch the .NET 10.0 Desktop Runtime download URL.${NC}"
    exit 1
fi

echo -e "Downloading .NET 10.0 from: $DOTNET_URL"
DOTNET_EXE="$VRC_COMPATDATA/pfx/drive_c/windowsdesktop-runtime-10.exe"
curl -L -o "$DOTNET_EXE" "$DOTNET_URL"

echo -e "${BLUE}Installing .NET 10.0 Desktop Runtime in VRChat prefix...${NC}"
# Run the installer silently
protontricks --no-bwrap -c "wine C:\\windowsdesktop-runtime-10.exe /quiet /norestart" 438100
echo -e "${GREEN}.NET 10.0 Desktop Runtime installed successfully.${NC}"

# 5. Download and Extract VRCOSC
echo -e "${BLUE}Fetching latest VRCOSC release version...${NC}"
LATEST_RELEASE_JSON=$(curl -s https://api.github.com/repos/VolcanicArts/VRCOSC/releases/latest)
NUPKG_URL=$(echo "$LATEST_RELEASE_JSON" | grep -o 'https://github.com/VolcanicArts/VRCOSC/releases/download/[^"]*live-full.nupkg' | head -n 1)

if [ -z "$NUPKG_URL" ]; then
    echo -e "${RED}Error: Failed to fetch the VRCOSC live package URL.${NC}"
    exit 1
fi

echo -e "Downloading VRCOSC package from: $NUPKG_URL"
NUPKG_FILE="/tmp/vrcosc-latest.nupkg"
curl -L -o "$NUPKG_FILE" "$NUPKG_URL"

# Extract to VRCOSC destination in user AppData/Local
VRCOSC_DIR="$VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Local/VRCOSC"
echo -e "${BLUE}Installing VRCOSC to $VRCOSC_DIR...${NC}"
mkdir -p "$VRCOSC_DIR"

# Clean old installation folder if it exists
rm -rf "$VRCOSC_DIR"/*

# Nupkg contains files inside lib/app/
TEMP_EXTRACT="/tmp/vrcosc-extract"
rm -rf "$TEMP_EXTRACT"
mkdir -p "$TEMP_EXTRACT"
unzip -q "$NUPKG_FILE" -d "$TEMP_EXTRACT"

# Copy lib/app contents to VRCOSC AppData destination
cp -r "$TEMP_EXTRACT/lib/app/"* "$VRCOSC_DIR/"
echo -e "${GREEN}VRCOSC files extracted successfully.${NC}"

# Cleanup temp files
rm -f "$REG_FILE" "$DOTNET_EXE" "$NUPKG_FILE"
rm -rf "$TEMP_EXTRACT"

# 6. Configure Firewall for OSC ports
echo -e "${BLUE}Configuring firewall for OSC and OSCQuery mDNS ports (9000/9001/5353 UDP)...${NC}"
if command -v firewall-cmd &>/dev/null; then
    echo "Using firewalld to open ports..."
    sudo -n firewall-cmd --add-port=9000/udp --permanent 2>/dev/null || true
    sudo -n firewall-cmd --add-port=9001/udp --permanent 2>/dev/null || true
    sudo -n firewall-cmd --add-port=5353/udp --permanent 2>/dev/null || true
    sudo -n firewall-cmd --reload 2>/dev/null || true
elif command -v ufw &>/dev/null; then
    echo "Using UFW to open ports..."
    sudo -n ufw allow 9000/udp 2>/dev/null || true
    sudo -n ufw allow 9001/udp 2>/dev/null || true
    sudo -n ufw allow 5353/udp 2>/dev/null || true
    sudo -n ufw reload 2>/dev/null || true
elif command -v iptables &>/dev/null; then
    echo "Using iptables to open ports..."
    sudo -n iptables -I INPUT -p udp --dport 9000 -j ACCEPT 2>/dev/null || true
    sudo -n iptables -I INPUT -p udp --dport 9001 -j ACCEPT 2>/dev/null || true
    sudo -n iptables -I INPUT -p udp --dport 5353 -j ACCEPT 2>/dev/null || true
else
    echo "No supported firewall manager found or sudo required. Ensure UDP ports 9000, 9001, and 5353 are allowed."
fi

# 7. Create Launch Script & Desktop Entry
echo -e "${BLUE}Creating launch script and desktop entry...${NC}"
LAUNCH_SCRIPT="$HOME/.local/bin/vrcosc"
mkdir -p "$(dirname "$LAUNCH_SCRIPT")"

cat << 'EOF' > "$LAUNCH_SCRIPT"
#!/usr/bin/env bash
# VRCOSC Launcher for Linux/Proton
ENTRY="C:/users/steamuser/AppData/Local/VRCOSC/VRCOSC.dll"
DOTNET="C:/Program Files/dotnet/dotnet.exe"

exec protontricks --no-bwrap -c "wine \"$DOTNET\" \"$ENTRY\" $*" 438100
EOF
chmod +x "$LAUNCH_SCRIPT"

DESKTOP_ENTRY="$HOME/.local/share/applications/vrcosc.desktop"
mkdir -p "$(dirname "$DESKTOP_ENTRY")"

cat << EOF > "$DESKTOP_ENTRY"
[Desktop Entry]
Name=VRCOSC
Comment=OSC controller for VRChat
Exec=$LAUNCH_SCRIPT
Icon=steam
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=VRCOSC
EOF

echo -e "${GREEN}=== VRCOSC Setup Complete! ===${NC}"
echo -e "You can launch VRCOSC from your application menu, or run '${BLUE}vrcosc${NC}' in the terminal."
echo -e "\n${BLUE}VRCOSC Directory Paths:${NC}"
echo -e "  * ${GREEN}Config Folder (Profiles & Settings):${NC}"
echo -e "    $VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Roaming/VRCOSC"
echo -e "  * ${GREEN}Executable Folder (App Files):${NC}"
echo -e "    $VRCOSC_DIR"
