#!/usr/bin/env bash

# VRCOSC automated installer and runner setup script for Bazzite / Linux
set -euo pipefail

# Visual styling
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
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
SEARCH_PATHS=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "/run/media/system/Data/Games/Steam"
    "/media/media-automount/Data/Games/Steam"
)

for path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$path/steamapps/compatdata/438100/pfx" ]; then
        VRC_COMPATDATA="$path/steamapps/compatdata/438100"
        echo -e "${GREEN}Found VRChat compatibility data at: $VRC_COMPATDATA${NC}"
        break
    fi
done

if [ -z "$VRC_COMPATDATA" ]; then
    echo -e "${RED}Error: Could not locate VRChat (438100) compatibility prefix.${NC}"
    echo "Make sure VRChat is installed and has been run at least once under Proton."
    exit 1
fi

# Ensure flatpak protontricks has access to the steam directories if running under flatpak
if flatpak list | grep -q "protontricks"; then
    echo -e "${BLUE}Updating flatpak permissions for protontricks...${NC}"
    flatpak override --user --filesystem=host com.github.Matoking.protontricks || true
fi

# 3. Apply WPF Hardware Acceleration Fix
echo -e "${BLUE}Applying WPF hardware acceleration registry fix...${NC}"
REG_FILE="$VRC_COMPATDATA/pfx/drive_c/vrcosc_disable_hw_acc.reg"
cat << 'EOF' > "$REG_FILE"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Microsoft\Avalon.Graphics]
"DisableHWAcceleration"=dword:00000001
EOF

protontricks -c "wine regedit C:\\vrcosc_disable_hw_acc.reg" 438100
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
protontricks -c "wine C:\\windowsdesktop-runtime-10.exe /quiet /norestart" 438100
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

# 6. Create Launch Script & Desktop Entry
echo -e "${BLUE}Creating launch script and desktop entry...${NC}"
LAUNCH_SCRIPT="$HOME/.local/bin/vrcosc"
mkdir -p "$(dirname "$LAUNCH_SCRIPT")"

cat << 'EOF' > "$LAUNCH_SCRIPT"
#!/usr/bin/env bash
exec protontricks -c "wine C:/users/steamuser/AppData/Local/VRCOSC/VRCOSC.exe" 438100
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
Categories=Game;Utility;
EOF

echo -e "${GREEN}=== VRCOSC Setup Complete! ===${NC}"
echo -e "You can launch VRCOSC from your application menu, or run '${BLUE}vrcosc${NC}' in the terminal."
echo -e "\n${BLUE}VRCOSC Directory Paths:${NC}"
echo -e "  * ${GREEN}Config Folder (Profiles & Settings):${NC}"
echo -e "    $VRC_COMPATDATA/pfx/drive_c/users/steamuser/AppData/Roaming/VRCOSC"
echo -e "  * ${GREEN}Executable Folder (App Files):${NC}"
echo -e "    $VRCOSC_DIR"

