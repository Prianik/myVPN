#!/bin/sh

echo ""
echo ".......Updating OPKG ......."
echo ""
opkg update 
echo ""
echo ".......Updating installed packages......."
echo ""
opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade

echo ""
echo  ".......Identifying the latest version ZAPRET......."
wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zver.txt
zver=$(cat zver.txt)
rm zver.txt
echo  "********Version ZAPRET ******"${zver}
echo ""
echo ""

echo ".......Installed or Update ZAPRET version-${zver} ......."
wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/luci-app-zapret_${zver}_all.ipk
wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zapret_${zver}_mipsel_24kc.ipk

opkg install zapret_${zver}_mipsel_24kc.ipk
opkg install luci-app-zapret_${zver}_all.ipk
rm zapret_${zver}_mipsel_24kc.ipk
rm luci-app-zapret_${zver}_all.ipk
service zapret restart
