#!/bin/sh

# OpenWRT Configuration Script
# Provides multiple modes for system management

# Configuration variables
ZAPRET_LUCI_PKG="luci-app-zapret_71.20250708-r1_all.ipk"
ZAPRET_PKG="zapret_71.20250708_mipsel_24kc.ipk"
ZAPRET_BASE_URL="https://github.com/Prianik/myVPN/raw/refs/heads/main/z"
DNS_FILES_URL="https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "Script failed at line $1 with exit code $2"
    exit $2
}

trap 'handle_error $LINENO $?' ERR

# Check internet connectivity
check_internet() {
    if ! ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        log_error "No internet connection. Please check your network."
        exit 1
    fi
}

# Download file with retry
download_file() {
    local url=$1
    local filename=$2
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if wget --show-progress -q "$url" -O "$filename"; then
            return 0
        fi
        retry_count=$((retry_count + 1))
        log_warning "Download failed, retry $retry_count/$max_retries..."
        sleep 2
    done
    
    log_error "Failed to download: $url"
    return 1
}

# Function for full automatic update mode
update_mode() {
    log_info "FULL AUTOMATIC UPDATE MODE SELECTED"
    
    check_internet
    
    # Update OPKG and install necessary packages
    log_info "Updating package lists..."
    if ! opkg update; then
        log_error "Failed to update package lists. Check internet connection or repo URLs."
        exit 1
    fi

    # Install required packages
    for pkg in ca-certificates wget-ssl; do
        if ! opkg list-installed | grep -q "^$pkg"; then
            log_info "Installing $pkg..."
            opkg install "$pkg" || {
                log_error "Failed to install $pkg"
                exit 1
            }
        fi
    done

    # Remove nfqws-keenetic packages
    log_info "Removing nfqws-keenetic packages..."
    if opkg list-installed | grep -q nfqws-keenetic; then
        opkg remove nfqws-keenetic* || {
            log_warning "Failed to remove nfqws-keenetic packages (continuing anyway)"
        }
    else
        log_info "nfqws-keenetic packages not found. Skipping removal."
    fi

    # Update installed packages
    log_info "Upgrading installed packages..."
    upgradable_pkgs=$(opkg list-upgradable | awk '{print $1}')
    if [ -n "$upgradable_pkgs" ]; then
        echo "$upgradable_pkgs" | xargs -r opkg upgrade
    else
        log_info "No packages to upgrade."
    fi

    # Update or install ZAPRET
    update_zapret

    # Update DNS for Instagram if ZAPRET is installed
    update_instagram_dns

    # Update or install https-dns-proxy
    log_info "Updating/Installing https-dns-proxy..."
    if opkg list-installed | grep -q https-dns-proxy; then
        log_info "https-dns-proxy is installed. Proceeding with update..."
        opkg install --force-reinstall https-dns-proxy luci-app-https-dns-proxy || {
            log_error "Failed to update https-dns-proxy"
            exit 1
        }
    else
        log_info "https-dns-proxy is not installed. Proceeding with installation..."
        opkg install https-dns-proxy luci-app-https-dns-proxy || {
            log_error "Failed to install https-dns-proxy"
            exit 1
        }
    fi
    
    service rpcd restart || {
        log_warning "Failed to restart rpcd (continuing anyway)"
    }

    log_success "Full automatic update completed successfully!"
}

# Function to update/install ZAPRET
update_zapret() {
    log_info "Updating/Installing ZAPRET..."
    
    local zapret_installed=$(opkg list-installed | grep -q zapret && echo "yes" || echo "no")
    
    if [ "$zapret_installed" = "yes" ]; then
        log_info "ZAPRET is installed. Proceeding with update..."
    else
        log_info "ZAPRET is not installed. Proceeding with installation..."
    fi

    # Download ZAPRET packages
    for pkg in "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG"; do
        download_file "$ZAPRET_BASE_URL/$pkg" "$pkg" || exit 1
    done

    # Install packages
    opkg install --force-reinstall "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG" || {
        log_error "Failed to install/update ZAPRET"
        rm -f "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG"
        exit 1
    }
    
    # Cleanup
    rm -f "$ZAPRET_PKG" "$ZAPRET_LUCI_PKG"
}

# Function to update Instagram DNS
update_instagram_dns() {
    if [ -d "/opt/zapret" ]; then
        log_info "Updating Instagram DNS..."
        
        for file in dns.txt ip.txt; do
            download_file "$DNS_FILES_URL/$file" "$file" || exit 1
        done

        cat dns.txt >> /opt/zapret/ipset/zapret-hosts-user.txt
        cat ip.txt >> /opt/zapret/ipset/zapret-ip-user.txt
        rm -f dns.txt ip.txt
        
        service zapret restart || {
            log_warning "Failed to restart ZAPRET service (continuing anyway)"
        }
    else
        log_info "ZAPRET directory not found. Skipping DNS update."
    fi
}

# Function for ZAPRET update only
zapret_update_mode() {
    log_info "ZAPRET UPDATE MODE SELECTED"
    check_internet
    update_zapret
    log_success "ZAPRET installation/update completed successfully!"
}

# Function for Instagram DNS update only
instagram_dns_mode() {
    log_info "INSTAGRAM DNS UPDATE MODE SELECTED"
    check_internet
    
    if [ -d "/opt/zapret" ]; then
        update_instagram_dns
        log_success "Instagram DNS update completed successfully!"
    else
        log_error "ZAPRET directory not found. Please install ZAPRET first (use mode 3 or 5)."
        exit 1
    fi
}

# Function for complete ZAPRET update with DNS
zapret_complete_mode() {
    log_info "COMPLETE ZAPRET UPDATE MODE SELECTED"
    check_internet
    update_zapret
    update_instagram_dns
    log_success "Complete ZAPRET update completed successfully!"
}

# Function for system configuration mode
system_config_mode() {
    log_info "SYSTEM CONFIGURATION MODE SELECTED"
    
    # Handle WiFi parameters
    if [ $# -eq 3 ]; then
        log_info "Wi-Fi parameters provided"
        NameSSID0=$1  # Wi-Fi 5 GHz SSID
        NameSSID1=$2  # Wi-Fi 2.4 GHz SSID
        WiFiKey=$3    # Wi-Fi password
    else
        log_info "No Wi-Fi parameters provided. Prompting for input..."
        read -p "Enter NameSSID for WiFi5: " NameSSID0
        read -p "Enter NameSSID for WiFi2.4: " NameSSID1
        read -s -p "Enter Wi-Fi password: " WiFiKey
        echo
    fi

    # Set timezone and time
    log_info "Configuring timezone and time..."
    uci set system.@system[0].zonename='Europe/Moscow'
    uci set system.@system[0].timezone='MSK-3'
    uci commit system || {
        log_error "Failed to commit system settings"
        exit 1
    }
    
    /etc/init.d/sysntpd restart || {
        log_warning "Failed to restart sysntpd (continuing anyway)"
    }

    # Setup crontab
    log_info "Setting up crontab..."
    {
        echo "#31 0 * * 1 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update.sh | sh"
        echo "#30 0 * * 0 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update-dns.sh | sh"
        echo "30 3 * * * /sbin/reboot"
    } >> /etc/crontabs/root
    
    /etc/init.d/cron restart || {
        log_warning "Failed to restart cron service"
    }

    # Configure Wi-Fi
    log_info "Configuring Wi-Fi..."
    
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
        log_error "Failed to commit Wi-Fi settings"
        exit 1
    }
    
    log_info "Wi-Fi configuration applied"

    # Set LAN IP address
    log_info "Setting LAN IP to 172.16.1.1..."
    uci set network.lan.ipaddr='172.16.1.1'
    uci commit network || {
        log_error "Failed to commit network settings"
        exit 1
    }
    
    if ! /etc/init.d/network restart; then
        log_warning "Failed to restart network (continuing anyway)"
    fi
    
    log_info "Local network IP address changed to 172.16.1.1"

    # Clean up temporary files
    rm -f ./*

    log_success "System configuration completed successfully!"
    log_info "NOTE: It's recommended to run Update mode first to ensure all packages are up to date."
}

# Main menu
show_menu() {
    echo ""
    echo "=========================================="
    echo " OpenWRT Configuration Script"
    echo "=========================================="
    echo ""
    echo "Select mode:"
    echo "1) Full automatic update (remove keenetic, update packages, ZAPRET, DNS, https-dns-proxy)"
    echo "2) System configuration (NET, WiFi, crontab)"
    echo "3) ZAPRET update/install (install if not present)"
    echo "4) Instagram DNS update only (requires ZAPRET)"
    echo "5) Complete ZAPRET update (install/update + DNS)"
    echo ""
    echo "Notes:"
    echo "- For System configuration, you can provide WiFi parameters as arguments:"
    echo "  $0 2 \"WiFi5_SSID\" \"WiFi2.4_SSID\" \"Password\""
    echo "- Mode 1 performs complete system maintenance automatically"
    echo "- Mode 3 will install ZAPRET if not installed, or update if installed"
    echo "- Mode 4 requires ZAPRET to be installed first"
    echo "- Mode 5 combines modes 3 and 4"
    echo ""
}

# Main execution
main() {
    show_menu
    read -p "Enter your choice (1-5): " choice

    case $choice in
        1)
            update_mode
            ;;
        2)
            system_config_mode "$@"
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
            log_error "Invalid choice. Please enter 1-5."
            exit 1
            ;;
    esac
}

# Run main function
main "$@"