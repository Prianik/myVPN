#!/bin/sh

# OpenWRT Configuration Script
# Provides multiple modes for system management

# Function for full automatic update mode
update_mode() {
    set -e # Exit on error for this mode
    echo ""
    echo ".......FULL AUTOMATIC UPDATE MODE SELECTED......."
    echo ""
    
    # Update OPKG and install necessary packages
    echo ".......Updating package lists......."
    if ! opkg update; then
        echo "❌ Error: Failed to update package lists. Check internet connection or repo URLs."
        exit 1
    fi

    opkg install ca-certificates wget-ssl || {
        echo "❌ Error: Failed to install required packages (ca-certificates, wget-ssl)."
        exit 1
    }

    # Remove nfqws-keenetic packages
    echo ""
    echo ".......Removing nfqws-keenetic packages......."
    echo ""
    if opkg list-installed | grep -q nfqws-keenetic; then
        opkg remove nfqws-keenetic* || {
            echo "⚠ Warning: Failed to remove nfqws-keenetic packages (continuing anyway)."
        }
    else
        echo "ℹ️  nfqws-keenetic packages not found. Skipping removal."
    fi

    # Update installed packages
    echo ""
    echo ".......Upgrading installed packages......."
    echo ""
    opkg list-upgradable | awk '{print $1}' | xargs -r opkg upgrade

    # Update or install ZAPRET
    echo ""
    echo ".......Updating/Installing ZAPRET......."
    echo ""
    
    # Update ZAPRET if installed, install if not installed
    if opkg list-installed | grep -q zapret; then
        echo "ℹ️  ZAPRET is installed. Proceeding with update..."
    else
        echo "ℹ️  ZAPRET is not installed. Proceeding with installation..."
    fi
    
    #-----------------------------------------------------------
    vluci=luci-app-zapret_71.20250708-r1_all.ipk
    vzapret=zapret_71.20250708_mipsel_24kc.ipk
    #-----------------------------------------------------------

    if ! wget --show-progress "https://github.com/Prianik/myVPN/raw/refs/heads/main/z/${vluci}" || \
       ! wget --show-progress "https://github.com/Prianik/myVPN/raw/refs/heads/main/z/${vzapret}"; then
        echo "❌ Error: Failed to download ZAPRET packages."
        exit 1
    fi

    if ! opkg install --force-reinstall "${vzapret}" || \
       ! opkg install --force-reinstall "${vluci}"; then
        echo "❌ Error: Failed to install/update ZAPRET."
        exit 1
    fi
    rm -f "${vzapret}"
    rm -f "${vluci}"
    
    # Update DNS for Instagram if ZAPRET is installed
    if [ -d "/opt/zapret" ]; then
        echo ""
        echo ".......Updating Instagram DNS......."
        echo ""
        if ! wget --show-progress https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/dns.txt || \
           ! wget --show-progress https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/ip.txt; then
            echo "❌ Error: Failed to download DNS/IP lists."
            exit 1
        fi
        cat dns.txt >> /opt/zapret/ipset/zapret-hosts-user.txt || exit 1
        cat ip.txt >> /opt/zapret/ipset/zapret-ip-user.txt || exit 1
        rm -f dns.txt
        rm -f ip.txt
        service zapret restart || {
            echo "⚠ Warning: Failed to restart ZAPRET service (continuing anyway)."
        }
    fi

    # Update or install https-dns-proxy
    echo ""
    echo ".......Updating/Installing https-dns-proxy......."
    echo ""
    if opkg list-installed | grep -q https-dns-proxy; then
        echo "ℹ️  https-dns-proxy is installed. Proceeding with update..."
        if ! opkg install --force-reinstall https-dns-proxy || ! opkg install --force-reinstall luci-app-https-dns-proxy; then
            echo "❌ Error: Failed to update https-dns-proxy."
            exit 1
        fi
    else
        echo "ℹ️  https-dns-proxy is not installed. Proceeding with installation..."
        if ! opkg install https-dns-proxy || ! opkg install luci-app-https-dns-proxy; then
            echo "❌ Error: Failed to install https-dns-proxy."
            exit 1
        fi
    fi
    
    service rpcd restart || {
        echo "⚠ Warning: Failed to restart rpcd (continuing anyway)."
    }

    echo ""
    echo "✅ Full automatic update completed successfully!......."
    echo ""
}

# Function for ZAPRET update only
zapret_update_mode() {
    set -e # Exit on error for this mode
    echo ""
    echo ".......ZAPRET UPDATE MODE SELECTED......."
    echo ""
    
    # Update ZAPRET if installed, install if not installed
    if opkg list-installed | grep -q zapret; then
        echo "ℹ️  ZAPRET is installed. Proceeding with update..."
        echo ""
        echo ".......Updating ZAPRET......."
        echo ""
    else
        echo "ℹ️  ZAPRET is not installed. Proceeding with installation..."
        echo ""
        echo ".......Installing ZAPRET......."
        echo ""
    fi
    
    #-----------------------------------------------------------
    vluci=luci-app-zapret_71.20250708-r1_all.ipk
    vzapret=zapret_71.20250708_mipsel_24kc.ipk
    #-----------------------------------------------------------

    if ! wget --show-progress "https://github.com/Prianik/myVPN/raw/refs/heads/main/z/${vluci}" || \
       ! wget --show-progress "https://github.com/Prianik/myVPN/raw/refs/heads/main/z/${vzapret}"; then
        echo "❌ Error: Failed to download ZAPRET packages."
        exit 1
    fi

    if ! opkg install --force-reinstall "${vzapret}" || \
       ! opkg install --force-reinstall "${vluci}"; then
        echo "❌ Error: Failed to install/update ZAPRET."
        exit 1
    fi
    rm -f "${vzapret}"
    rm -f "${vluci}"
    
    # Update DNS for Instagram after ZAPRET installation/update
    if [ -d "/opt/zapret" ]; then
        echo ""
        echo ".......Updating Instagram DNS......."
        echo ""
        if ! wget --show-progress https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/dns.txt || \
           ! wget --show-progress https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/ip.txt; then
            echo "❌ Error: Failed to download DNS/IP lists."
            exit 1
        fi
        cat dns.txt >> /opt/zapret/ipset/zapret-hosts-user.txt || exit 1
        cat ip.txt >> /opt/zapret/ipset/zapret-ip-user.txt || exit 1
        rm -f dns.txt
        rm -f ip.txt
        service zapret restart || {
            echo "⚠ Warning: Failed to restart ZAPRET service (continuing anyway)."
        }
    fi
    
    echo ""
    echo "✅ ZAPRET installation/update completed successfully!......."
    echo ""
}

# Function for Instagram DNS update only
instagram_dns_mode() {
    set -e # Exit on error for this mode
    echo ""
    echo ".......INSTAGRAM DNS UPDATE MODE SELECTED......."
    echo ""
    
    # Update DNS for Instagram if ZAPRET is installed
    if [ -d "/opt/zapret" ]; then
        echo ""
        echo ".......Updating Instagram DNS......."
        echo ""
        if ! wget --show-progress https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/dns.txt || \
           ! wget --show-progress https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main/ip.txt; then
            echo "❌ Error: Failed to download DNS/IP lists."
            exit 1
        fi
        cat dns.txt >> /opt/zapret/ipset/zapret-hosts-user.txt || exit 1
        cat ip.txt >> /opt/zapret/ipset/zapret-ip-user.txt || exit 1
        rm -f dns.txt
        rm -f ip.txt
        service zapret restart || {
            echo "⚠ Warning: Failed to restart ZAPRET service (continuing anyway)."
        }
    else
        echo "ℹ️  ZAPRET directory not found. Please install ZAPRET first (use mode 3 or 5)."
        exit 1
    fi
    
    echo ""
    echo "✅ Instagram DNS update completed successfully!......."
    echo ""
}

# Function for complete ZAPRET update with DNS
zapret_complete_mode() {
    set -e # Exit on error for this mode
    echo ""
    echo ".......COMPLETE ZAPRET UPDATE MODE SELECTED......."
    echo ""
    
    zapret_update_mode
    
    echo ""
    echo "✅ Complete ZAPRET update completed successfully!......."
    echo ""
}

# Function for clean install mode
clean_install_mode() {
    set -e # Exit on error for this mode
    echo ""
    echo ".......CLEAN INSTALL MODE SELECTED......."
    echo ""
    
    # Check for WiFi parameters
    if [ $# -eq 3 ]; then
        echo ".......Wi-Fi parameters provided........"
        NameSSID0=$1  # Wi-Fi 5 GHz SSID
        NameSSID1=$2  # Wi-Fi 2.4 GHz SSID
        WiFiKey=$3    # Wi-Fi password
        echo "Using provided Wi-Fi credentials."
    else
        echo ".......No Wi-Fi parameters provided. Prompting for input........"
        read -p "Enter NameSSID for WiFi5: " NameSSID0
        read -p "Enter NameSSID for WiFi2.4: " NameSSID1
        read -p "Enter Wi-Fi password: " WiFiKey
    fi

    # Set timezone and time
    echo ""
    echo ".......Configuring timezone and time......."
    echo ""
    uci set system.@system[0].zonename='Europe/Moscow'
    uci set system.@system[0].timezone='MSK-3'
    uci commit system || exit 1
    /etc/init.d/sysntpd restart || {
        echo "⚠ Warning: Failed to restart sysntpd (continuing anyway)."
    }

echo ""
echo ".......Setting up crontab......."
echo ""
echo "#31 0 * * 1 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update.sh | sh" >> /etc/crontabs/root
echo "#30 0 * * 0 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update-dns.sh | sh" >> /etc/crontabs/root
echo "30 3 * * * /sbin/reboot " >> /etc/crontabs/root
/etc/init.d/cron restart

    # Configure Wi-Fi
    echo ""
    echo ".......Configuring Wi-Fi......."
    echo ""
    
    # Configure Wi-Fi 5 GHz (radio0)
    uci set wireless.@wifi-iface[0].device='radio0'
    uci set wireless.@wifi-iface[0].mode='ap'
    uci set wireless.@wifi-iface[0].disabled=0
    uci set wireless.@wifi-iface[0].ssid="$NameSSID0"
    uci set wireless.@wifi-iface[0].network='lan'
    uci set wireless.@wifi-iface[0].encryption='psk2'
    uci set wireless.@wifi-iface[0].key="$WiFiKey"
    uci set wireless.radio0.disabled=0

    # Configure Wi-Fi 2.4 GHz (radio1)
    uci set wireless.@wifi-iface[1].device='radio1'
    uci set wireless.@wifi-iface[1].mode='ap'
    uci set wireless.@wifi-iface[1].disabled=0
    uci set wireless.@wifi-iface[1].ssid="$NameSSID1"
    uci set wireless.@wifi-iface[1].network='lan'
    uci set wireless.@wifi-iface[1].encryption='psk2'
    uci set wireless.@wifi-iface[1].key="$WiFiKey"
    uci set wireless.radio1.disabled=0

    # Apply Wi-Fi settings
    uci commit wireless || {
        echo "❌ Error: Failed to commit Wi-Fi settings."
        exit 1
    }
    echo ""
    echo ".......Wi-Fi configuration applied........"
    echo ""

    # Set LAN IP address
    echo ""
    echo ".......Setting LAN IP to 172.16.1.1......."
    echo ""
    uci set network.lan.ipaddr='172.16.1.1'
    uci commit network || {
        echo "❌ Error: Failed to commit network settings."
        exit 1
    }
    if ! /etc/init.d/network restart; then
        echo "⚠ Warning: Failed to restart network (continuing anyway)."
    fi
    echo ""
    echo ".......Local network IP address changed to 172.16.1.1........"
    echo ""

    # Clean up temporary files
    rm -f ./*

    echo ""
    echo "✅ Clean installation completed successfully!......."
    echo ""
    echo "NOTE: It's recommended to run Update mode first to ensure all packages are up to date."
    echo ""
}

# Main menu
echo ""
echo "=========================================="
echo " OpenWRT Configuration Script"
echo "=========================================="
echo ""
echo "Select mode:"
echo "1) Full automatic update (remove keenetic, update packages, ZAPRET, DNS, https-dns-proxy)"
echo "2) Set NET, Wifi, crontab ... "
echo "3) ZAPRET update/install (install if not present)"
echo "4) Instagram DNS update only (requires ZAPRET)"
echo "5) Complete ZAPRET update (install/update + DNS)"
echo ""
echo "Notes:"
echo "- For Clean install, you can provide WiFi parameters as arguments:"
echo "  $0 2 \"WiFi5_SSID\" \"WiFi2.4_SSID\" \"Password\""
echo "- Mode 1 performs complete system maintenance automatically"
echo "- Mode 3 will install ZAPRET if not installed, or update if installed"
echo "- Mode 4 requires ZAPRET to be installed first"
echo "- Mode 5 combines modes 3 and 4"
echo ""
read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        update_mode
        ;;
    2)
        clean_install_mode "$@"
        ;;
    3)
        zapret_update_mode
        ;;
    4)
        instagram_dns_mode
        ;;
    5)
        zapret_complete_mode
        ;;
    *)
        echo "❌ Invalid choice. Please enter 1-5."
        exit 1
        ;;
esac
