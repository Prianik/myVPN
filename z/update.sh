#!/bin/sh

#echo ""
#echo ".......Updating OPKG ......."
#echo ""
#opkg update 
#echo ""
#echo ".......Updating installed packages......."
#echo ""
#opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade

a1=$(opkg list-installed | grep app-zapret | awk '{print $3 + 0}')
echo ""
echo ".......Installed version-${a1} ......."
echo ""

wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zver.txt
zver=$(cat zver.txt | awk '{print $1 + 0}')
echo ""
echo ".......Version update ${zver} ......."
echo ""
rm zver.txt

if [ ${a1} -gt ${zver} ]; then
    echo ""
    echo ".......Installed or Update ZAPRET version-${zver} ......."
    echo ""
    wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/luci-app-zapret_${zver}_all.ipk
    wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zapret_${zver}_mipsel_24kc.ipk
    opkg install zapret_${zver}_mipsel_24kc.ipk
    opkg install luci-app-zapret_${zver}_all.ipk
    rm zapret_${zver}_mipsel_24kc.ipk
    rm luci-app-zapret_${zver}_all.ipk
    service zapret restart
else
    echo ""
    echo  "......no new versions found...... "
    echo ""
fi




