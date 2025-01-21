#/bin/sh

opkg update 
opkg install ca-certificates wget-ssl
opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade


wget -O "/tmp/nfqws-keenetic.pub" "https://anonym-tsk.github.io/nfqws-keenetic/openwrt/nfqws-keenetic.pub"
opkg-key add /tmp/nfqws-keenetic.pub
echo "src/gz nfqws-keenetic https://anonym-tsk.github.io/nfqws-keenetic/openwrt" > /etc/opkg/nfqws-keenetic.conf
opkg update && opkg install nfqws-keenetic && opkg install nfqws-keenetic-web

opkg install https-dns-proxy && opkg install luci-app-https-dns-proxy && service rpcd restart


#cat /etc/crontabs/root
echo  "24 0 * * 1 /bin/opkg update" >> /etc/crontabs/root
echo  "29 0 * * 1 /bin/opkg upgrade nfqws-keenetic && /bin/opkg upgrade nfqws-keenetic-web"  >> /etc/crontabs/root

#https://community.antifilter.download/
#INSTAGRAM
cp /etc/nfqws/user.list /etc/nfqws/user.list.bak
echo "instagram.com" >> /etc/nfqws/user.list
echo "instagram.fhrk1-1.fna.fbcdn.net" >> /etc/nfqws/user.list
echo "instagram.fkun2-1.fna.fbcdn.net" >> /etc/nfqws/user.list
echo "instagram.frix7-1.fna.fbcdn.net" >> /etc/nfqws/user.list
echo "instagram.fvno2-1.fna.fbcdn.net" >> /etc/nfqws/user.list
echo "cdninstagram.com" >> /etc/nfqws/user.list
echo "igcdn-photos-e-a.akamaihd.net" >> /etc/nfqws/user.list
echo "instagramstatic.com" >> /etc/nfqws/user.list
echo "scontent-hel3-1.cdninstagram.com" >> /etc/nfqws/user.list
echo "static.cdninstagram.com" >> /etc/nfqws/user.list
echo "scontent-arn2-1.cdninstagram.com" >> /etc/nfqws/user.list
echo "scontent.cdninstagram.com" >> /etc/nfqws/user.list
echo "edge-chat.instagram.com" >> /etc/nfqws/user.list
echo "graph.instagram.com" >> /etc/nfqws/user.list
echo "gateway.instagram.com" >> /etc/nfqws/user.list
echo "kino.pub" >> /etc/nfqws/user.list
echo "rutracker.org" >> /etc/nfqws/user.list
echo "rutracker.ru" >> /etc/nfqws/user.list
service nfqws-keenetic restart
#
system.@system[0].zonename='Europe/Moscow'
uci set system.@system[0].timezone='MSK-3'
uci commit system
timezone=$(uci get system.@system[0].timezone); [ -z "$timezone" ] && timezone=UTC; echo "$timezone" > /tmp/TZ


#NameSSID0=RT-5WiFi-AE72
#NameSSID1=RT-WiFi-AE72
#WiFiKey=R7aAPz5Y
read -p "Enter NameSSID WiFi5: " NameSSID0 && read -p "Enter NameSSID WiFi2.4: " NameSSID1 && read -p "Enter WiFi password: " WiFiKey

#uci set wireless.radio0.distance=100
#uci set wireless.radio0.country='RU'
#uci set wireless.@wifi-iface[0].disabled=1


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
uci commit wireless

