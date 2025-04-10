#!/bin/sh

###!/usr/bin/env bash
####!/usr/bin/env sh
echo ".......Updating OPKG and updating installed packages"
opkg update 
opkg install ca-certificates wget-ssl
opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade

echo ".......Installed nfqws"
wget -O "/tmp/nfqws-keenetic.pub" "https://anonym-tsk.github.io/nfqws-keenetic/openwrt/nfqws-keenetic.pub"
opkg-key add /tmp/nfqws-keenetic.pub
echo "src/gz nfqws-keenetic https://anonym-tsk.github.io/nfqws-keenetic/openwrt" > /etc/opkg/nfqws-keenetic.conf

opkg update
opkg install nfqws-keenetic
opkg install nfqws-keenetic-web

echo ".......Installed https-dns-proxy"
opkg install https-dns-proxy
opkg install luci-app-https-dns-proxy
service rpcd restart

#cat /etc/crontabs/root
#echo  "24 0 * * 1 /bin/opkg update" >> /etc/crontabs/root
#echo  "29 0 * * 1 /bin/opkg upgrade nfqws-keenetic && /bin/opkg upgrade nfqws-keenetic-web"  >> /etc/crontabs/root

#https://community.antifilter.download/

echo ".......ADD dns instagram"
wget https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/dns.txt
cp /etc/nfqws/user.list /etc/nfqws/user.list.bak
cat dns.txt >> /etc/nfqws/user.list
service nfqws-keenetic restart
#
echo ".......SET Timezone and time"
uci set system.@system[0].zonename='Europe/Moscow'
uci set system.@system[0].timezone='MSK-3'
uci commit system
#timezone=$(uci get system.@system[0].timezone); [ -z "$timezone" ] && timezone=UTC; echo "$timezone" > /tmp/TZ
/etc/init.d/sysntpd restart

echo ".......SET crontab"
#echo  "24 0 * * 1 /bin/opkg update" >> /etc/crontabs/root
#echo  "29 0 * * 1 /bin/opkg upgrade nfqws-keenetic && /bin/opkg upgrade nfqws-keenetic-web"  >> /etc/crontabs/root


echo ".......SET WiFi"
if [ $# -eq 3 ]; then
    echo  "Parameters WiFi OK. "
    NameSSID0=$1
    NameSSID1=$2
    WiFiKey=$3
else
    echo  "No parameters WiFi found. "
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
wifi

echo ".......SET IP LAN 172.16.1.1"
echo "uci set network.lan.ipaddr='172.16.1.1' && uci commit network && /etc/init.d/network restart"
uci set network.lan.ipaddr='172.16.1.1'
uci commit network
echo ".......Local network IP address changed to 172.16.1.1 !!!!!!!!!!"
/etc/init.d/network restart
rm *


