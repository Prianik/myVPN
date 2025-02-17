#!/bin/sh

# Update OPKG
echo ""
echo ".......Updating OPKG......."
echo ""
opkg update

# Update installed packages
echo ""
echo ".......Updating installed packages......."
echo ""
opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade

# Get the currently installed version of app-zapret
a1=$(opkg list-installed | grep app-zapret | awk '{print $3}')
echo ""
echo ".......Installed version-${a1}......."
echo ""

# Download and read the version from zver.txt
echo ""
echo ".......Downloading version info......."
echo ""
wget -q https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zver.txt
zver=$(cat zver.txt)
echo ""
echo ".......Update version ${zver}......."
echo ""

# Remove the temporary file
rm -f zver.txt

# Compare versions and update if necessary
if [ "${a1}" != "${zver}" ]; then
    echo ""
    echo ".......Installing or updating ZAPRET version-${zver}......."
    echo ""

# Download  new packages
    wget -q https://github.com/Prianik/myVPN/raw/refs/heads/main/z/luci-app-zapret_${zver}_all.ipk
    wget -q https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zapret_${zver}_mipsel_24kc.ipk

# Install new packages
    opkg install  zapret_${zver}_mipsel_24kc.ipk
    opkg install  luci-app-zapret_${zver}_all.ipk

# Remove temporary files
    rm -f zapret_${zver}_mipsel_24kc.ipk
    rm -f luci-app-zapret_${zver}_all.ipk

# Restart the service
    service zapret restart
else
    echo ""
    echo ".......No new versions found......."
    echo ""
fi
