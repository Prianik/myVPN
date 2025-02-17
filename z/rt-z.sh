#!/bin/sh

#https://github.com/Prianik/myVPN/raw/refs/heads/main/z/rt-z.sh
#https://github.com/remittor/zapret-openwrt/releases
echo ""
echo ".......Updating OPKG ......."
echo ""
opkg update 
opkg install ca-certificates wget-ssl

echo ""
echo ".......Updating installed packages ......."
echo ""
opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade

echo ""
echo  ".......Identifying the latest version ZAPRET ......."
wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zver.txt
zver=$(cat zver.txt)
rm zver.txt
echo  "********Version ZAPRET ******"${zver}
echo ""
echo ""

echo ".......Installed ZAPRET version-${zver} -......."
wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/luci-app-zapret_${zver}_all.ipk
wget  https://github.com/Prianik/myVPN/raw/refs/heads/main/z/zapret_${zver}_mipsel_24kc.ipk

opkg install zapret_${zver}_mipsel_24kc.ipk
opkg install luci-app-zapret_${zver}_all.ipk
rm zapret_${zver}_mipsel_24kc.ipk
rm luci-app-zapret_${zver}_all.ipk

echo ""
echo ".......-ADD dns instagram ......."
echo ""
wget https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/dns.txt
cat dns.txt >> /opt/zapret/ipset/zapret-hosts-user.txt
service zapret restart

echo ""
echo ".......Installed https-dns-proxy ......."
echo ""
opkg install https-dns-proxy
opkg install luci-app-https-dns-proxy
service rpcd restart

echo ""
echo ".......SET crontab"
echo  "#24 0 * * 1 wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update.sh | sh" >> /etc/crontabs/root
echo ""

echo ""
echo ".......SET Timezone and time ......."
echo ""
uci set system.@system[0].zonename='Europe/Moscow'
uci set system.@system[0].timezone='MSK-3'
uci commit system
/etc/init.d/sysntpd restart

echo ""
echo ".......SET WiFi ......."
echo ""
if [ $# -eq 3 ]; then
    echo  ".......Parameters WiFi OK........ "
    NameSSID0=$1
    NameSSID1=$2
    WiFiKey=$3
else
    echo  ".......No parameters WiFi found........ "
    read -p "Enter NameSSID WiFi5: " NameSSID0
    read -p "Enter NameSSID WiFi2.4: " NameSSID1
    read -p "Enter WiFi password: " WiFiKey
fi

# set wifi managed (AP) mode
uci set wireless.@wifi-iface[0].device=radio0
#uci set wireless.radio0.channel='auto'
uci set wireless.@wifi-iface[0].mode='ap'
uci set wireless.@wifi-iface[0].disabled=0
uci set wireless.@wifi-iface[0].ssid=$NameSSID0
uci set wireless.@wifi-iface[0].network='lan'
uci set wireless.@wifi-iface[0].encryption=psk2
uci set wireless.@wifi-iface[0].key=$WiFiKey
uci set wireless.radio0.disabled=0
#uci set wireless.@wifi-iface[0].wps_pushbutton='0'
uci commit wireless

uci set wireless.@wifi-iface[1].device=radio1
#uci set wireless.radio1.channel='auto'
uci set wireless.@wifi-iface[1].mode='ap'
uci set wireless.@wifi-iface[1].disabled=0
uci set wireless.@wifi-iface[1].ssid=$NameSSID1
uci set wireless.@wifi-iface[1].network='lan'
uci set wireless.@wifi-iface[1].encryption=psk2
uci set wireless.@wifi-iface[1].key=$WiFiKey
uci set wireless.radio1.disabled=0
#uci set wireless.@wifi-iface[1].wps_pushbutton='0' 
uci commit wireless

echo ""
echo ".......SET IP LAN 172.16.1.1 ......."
echo ""
echo "uci set network.lan.ipaddr='172.16.1.1' && uci commit network && /etc/init.d/network restart"
uci set network.lan.ipaddr='172.16.1.1'
uci commit network
echo ""
echo  "Parameters Local network OK ........ "
echo ".......Local network IP address changed to 172.16.1.1 !!!!!!!!!! ......."
/etc/init.d/network restart
rm *


#смещениее в bin
#000600E0
#4yas8rad
