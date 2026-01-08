#!/bin/sh

# OpenWRT Configuration Script for Zapret (https://github.com/remittor/zapret-openwrt)
# Optimized for S1010 router with OpenWRT

# ============================================================================
# CONFIGURATION
# ============================================================================
readonly ZAPRET_BASE_URL="https://github.com/Prianik/myVPN/raw/refs/heads/main/z"
readonly DNS_FILES_URL="https://raw.githubusercontent.com/Prianik/myVPN/refs/heads/main"
readonly BACKUP_DIR="/root"
readonly BACKUP_FILE="$BACKUP_DIR/config_backup.tar.gz"
readonly LOG_FILE="/tmp/rt-z3d.log"
readonly TEMP_DIR="/tmp/rt-z3d"

# Retry parameters
readonly MAX_RETRIES=3
readonly RETRY_DELAY=2

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color="$NC"
    
    case "$level" in
        "INFO")    color="$BLUE"; symbol="ℹ️" ;;
        "SUCCESS") color="$GREEN"; symbol="✅" ;;
        "WARNING") color="$YELLOW"; symbol="⚠️" ;;
        "ERROR")   color="$RED"; symbol="❌" ;;
        *)         color="$NC"; symbol="📝" ;;
    esac
    
    echo -e "${color}${symbol} ${timestamp} ${message}${NC}"
    echo "${timestamp} ${level}: ${message}" >> "$LOG_FILE"
}

log_info() { log "INFO" "$1"; }
log_success() { log "SUCCESS" "$1"; }
log_warning() { log "WARNING" "$1"; }
log_error() { log "ERROR" "$1"; }

# ============================================================================
# ERROR HANDLING
# ============================================================================
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null
    log_info "Cleaned up temporary files"
}

handle_error() {
    local line=$1
    local code=$2
    log_error "Script failed at line $line with exit code $code"
    cleanup
    exit "$code"
}

trap 'handle_error $LINENO $?' ERR
trap cleanup EXIT

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_internet() {
    log_info "Checking internet connectivity..."
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && \
       ! ping -c 1 -W 3 github.com >/dev/null 2>&1; then
        log_error "No internet connection. Please check your network."
        exit 1
    fi
    log_success "Internet connection OK"
}

download_with_retry() {
    local url="$1"
    local output="$2"
    local retry=0
    
    while [ $retry -lt $MAX_RETRIES ]; do
        if wget --show-progress -q "$url" -O "$output"; then
            return 0
        fi
        retry=$((retry + 1))
        log_warning "Download failed ($retry/$MAX_RETRIES): $(basename "$url")"
        sleep $RETRY_DELAY
    done
    
    log_error "Failed to download: $(basename "$url")"
    return 1
}

is_installed() {
    opkg list-installed | grep -q "^$1 "
    return $?
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================
backup_config() {
    log_info "Creating configuration backup..."
    mkdir -p "$BACKUP_DIR"
    
    local config_files=(
        "/etc/config/network"
        "/etc/config/wireless"
        "/etc/config/system"
        "/etc/crontabs/root"
    )
    
    local existing_files=""
    for file in "${config_files[@]}"; do
        [ -f "$file" ] && existing_files="$existing_files $file"
    done
    
    if [ -n "$existing_files" ]; then
        if tar -czf "$BACKUP_FILE" $existing_files 2>/dev/null; then
            log_success "Backup created: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
            echo "To download: scp root@$(uci get network.lan.ipaddr 2>/dev/null || echo 'ROUTER_IP'):$BACKUP_FILE ."
            return 0
        fi
    fi
    
    log_error "Backup creation failed"
    return 1
}

restore_config() {
    log_info "Restoring configuration..."
    
    if [ -f "$BACKUP_FILE" ]; then
        if tar -xzf "$BACKUP_FILE" -C / 2>/dev/null; then
            log_success "Configuration restored from archive"
        else
            log_error "Failed to extract backup archive"
            return 1
        fi
    else
        log_error "Backup file not found: $BACKUP_FILE"
        return 1
    fi
    
    # Restart services
    for service in network firewall dnsmasq; do
        if [ -f "/etc/init.d/$service" ]; then
            /etc/init.d/"$service" restart 2>/dev/null && \
            log_info "Restarted $service" || \
            log_warning "Failed to restart $service"
        fi
    done
    
    # Clean up
    rm -f "$BACKUP_FILE"
    log_success "Restore completed"
    return 0
}

# ============================================================================
# ZAPRET FUNCTIONS
# ============================================================================
load_zapret_version() {
    local ver_file="ZAPRET_VER.txt"
    local temp_file="$TEMP_DIR/$ver_file"
    
    mkdir -p "$TEMP_DIR"
    log_info "Loading Zapret version information..."
    
    if ! download_with_retry "$ZAPRET_BASE_URL/$ver_file" "$temp_file"; then
        log_error "Cannot load Zapret version file"
        return 1
    fi
    
    # Source the version file
    if ! . "$temp_file" 2>/dev/null; then
        log_error "Invalid version file format"
        return 1
    fi
    
    # Validate required variables
    if [ -z "$ZAPRET_PKG" ] || [ -z "$ZAPRET_LUCI_PKG" ]; then
        log_error "Missing package definitions in version file"
        return 1
    fi
    
    log_success "Zapret version loaded: $(echo "$ZAPRET_PKG" | grep -o 'zapret-[0-9.]*')"
    return 0
}

update_zapret() {
    log_info "Processing Zapret..."
    
    if ! load_zapret_version; then
        return 1
    fi
    
    # Check current installation
    local zapret_installed=$(is_installed "zapret" && echo "yes" || echo "no")
    log_info "Zapret installed: $zapret_installed"
    
    # Download packages
    local packages=("$ZAPRET_PKG" "$ZAPRET_LUCI_PKG")
    for pkg in "${packages[@]}"; do
        log_info "Downloading: $pkg"
        if ! download_with_retry "$ZAPRET_BASE_URL/$pkg" "$TEMP_DIR/$pkg"; then
            log_error "Failed to download $pkg"
            return 1
        fi
    done
    
    # Install/update
    log_info "Installing/updating Zapret..."
    if ! opkg install --force-reinstall "$TEMP_DIR/$ZAPRET_PKG" "$TEMP_DIR/$ZAPRET_LUCI_PKG"; then
        log_error "Zapret installation failed"
        return 1
    fi
    
    log_success "Zapret processed successfully"
    return 0
}

update_instagram_dns() {
    if [ ! -d "/opt/zapret" ]; then
        log_info "Zapret directory not found, skipping DNS update"
        return 0
    fi
    
    log_info "Updating Instagram DNS..."
    
    local dns_files=("dns.txt" "dns-ext.txt" "ip.txt")
    for file in "${dns_files[@]}"; do
        if ! download_with_retry "$DNS_FILES_URL/$file" "$TEMP_DIR/$file"; then
            log_error "Failed to download $file"
            return 1
        fi
    done
    
    # Append to user files
    cat "$TEMP_DIR/dns.txt" >> /opt/zapret/ipset/zapret-hosts-user.txt 2>/dev/null
    cat "$TEMP_DIR/ip.txt" >> /opt/zapret/ipset/zapret-ip-user.txt 2>/dev/null
    cat "$TEMP_DIR/dns-ext.txt" >> /opt/zapret/ipset/zapret-hosts-user-exclude.txt 2>/dev/null
    
    # Restart service
    if [ -f "/etc/init.d/zapret" ]; then
        service zapret restart 2>/dev/null && \
        log_info "Zaprestarted" || \
        log_warning "Failed to restart Zapret"
    fi
    
    log_success "Instagram DNS updated"
    return 0
}

# ============================================================================
# SYSTEM FUNCTIONS
# ============================================================================
install_prerequisites() {
    log_info "Installing prerequisites..."
    
    local prerequisites=("ca-certificates" "wget-ssl")
    for pkg in "${prerequisites[@]}"; do
        if ! is_installed "$pkg"; then
            log_info "Installing $pkg..."
            if ! opkg install "$pkg"; then
                log_error "Failed to install $pkg"
                return 1
            fi
        fi
    done
    
    log_success "Prerequisites installed"
    return 0
}

remove_keenetic() {
    if is_installed "nfqws-keenetic"; then
        log_info "Removing nfqws-keenetic packages..."
        opkg remove nfqws-keenetic* 2>/dev/null || \
        log_warning "Some keenetic packages could not be removed"
    else
        log_info "nfqws-keenetic not found"
    fi
}

update_packages() {
    log_info "Updating package lists..."
    if ! opkg update; then
        log_error "Package list update failed"
        return 1
    fi
    
    log_info "Checking for upgrades..."
    local upgradable=$(opkg list-upgradable | awk '{print $1}')
    
    if [ -n "$upgradable" ]; then
        log_info "Upgrading $(echo "$upgradable" | wc -w) packages..."
        echo "$upgradable" | xargs -r opkg upgrade
        log_success "Package upgrade completed"
    else
        log_info "No packages to upgrade"
    fi
    
    return 0
}

install_https_dns_proxy() {
    log_info "Processing https-dns-proxy..."
    
    if ! opkg install --force-reinstall https-dns-proxy luci-app-https-dns-proxy; then
        log_error "Failed to install https-dns-proxy"
        return 1
    fi
    
    # Restart rpcd for LuCI
    if [ -f "/etc/init.d/rpcd" ]; then
        service rpcd restart 2>/dev/null
    fi
    
    log_success "https-dns-proxy installed"
    return 0
}

configure_system() {
    local ssid5="$1"
    local ssid24="$2"
    local wifi_key="$3"
    
    log_info "Configuring system settings..."
    
    # Timezone
    uci set system.@system[0].zonename='Europe/Moscow'
    uci set system.@system[0].timezone='MSK-3'
    uci commit system
    
    # Crontab
    log_info "Setting up scheduled tasks..."
    local cron_lines=(
        "#31 0 * * 1 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update.sh | sh"
        "#30 0 * * 0 /usr/bin/wget -qO - https://github.com/Prianik/myVPN/raw/refs/heads/main/z/update-dns.sh | sh"
        "30 3 * * * /sbin/reboot"
    )
    
    for line in "${cron_lines[@]}"; do
        echo "$line" >> /etc/crontabs/root
    done
    
    /etc/init.d/cron restart 2>/dev/null
    
    # WiFi configuration if parameters provided
    if [ -n "$ssid5" ] && [ -n "$ssid24" ] && [ -n "$wifi_key" ]; then
        log_info "Configuring WiFi..."
        
        # Radio 0 (5GHz)
        uci set wireless.@wifi-iface[0].device='radio0'
        uci set wireless.@wifi-iface[0].mode='ap'
        uci set wireless.@wifi-iface[0].disabled=0
        uci set wireless.@wifi-iface[0].ssid="$ssid5"
        uci set wireless.@wifi-iface[0].network='lan'
        uci set wireless.@wifi-iface[0].encryption='psk2'
        uci set wireless.@wifi-iface[0].key="$wifi_key"
        uci set wireless.radio0.disabled=0
        
        # Radio 1 (2.4GHz)
        uci set wireless.@wifi-iface[1].device='radio1'
        uci set wireless.@wifi-iface[1].mode='ap'
        uci set wireless.@wifi-iface[1].disabled=0
        uci set wireless.@wifi-iface[1].ssid="$ssid24"
        uci set wireless.@wifi-iface[1].network='lan'
        uci set wireless.@wifi-iface[1].encryption='psk2'
        uci set wireless.@wifi-iface[1].key="$wifi_key"
        uci set wireless.radio1.disabled=0
        
        uci commit wireless
    fi
    
    # Network
    uci set network.lan.ipaddr='172.16.1.1'
    uci commit network
    
    # Restart services
    /etc/init.d/network restart 2>/dev/null
    /etc/init.d/sysntpd restart 2>/dev/null
    
    log_success "System configuration completed"
    return 0
}

factory_reset() {
    log_warning "=== FACTORY RESET ==="
    log_warning "All settings will be lost!"
    log_warning "====================="
    
    read -p "Are you sure? Type 'YES' to confirm: " confirm
    if [ "$confirm" != "YES" ]; then
        log_info "Factory reset cancelled"
        return 1
    fi
    
    log_info "Performing factory reset..."
    firstboot -y && reboot
    return 0
}

# ============================================================================
# MODE FUNCTIONS
# ============================================================================
mode_full_install() {
    log_info "=== FULL INSTALL MODE ==="
    check_internet
    backup_config
    
    # Update mode
    install_prerequisites
    remove_keenetic
    update_packages
    update_zapret
    update_instagram_dns
    install_https_dns_proxy
    
    # Configuration mode
    if [ $# -ge 3 ]; then
        configure_system "$1" "$2" "$3"
    else
        configure_system
    fi
    
    log_success "Full installation completed"
}

mode_update_only() {
    log_info "=== UPDATE ONLY MODE ==="
    check_internet
    install_prerequisites
    remove_keenetic
    update_packages
    update_zapret
    update_instagram_dns
    install_https_dns_proxy
    log_success "Update completed"
}

mode_configure() {
    log_info "=== CONFIGURATION MODE ==="
    if [ $# -ge 3 ]; then
        configure_system "$1" "$2" "$3"
    else
        log_info "No WiFi parameters provided"
        read -p "Enter 5GHz SSID: " ssid5
        read -p "Enter 2.4GHz SSID: " ssid24
        read -s -p "Enter WiFi password: " wifi_key
        echo
        configure_system "$ssid5" "$ssid24" "$wifi_key"
    fi
}

mode_zapret_dns() {
    log_info "=== ZAPRET DNS MODE ==="
    check_internet
    update_zapret
    update_instagram_dns
    log_success "Zapret DNS updated"
}

mode_factory_reset_restore() {
    log_info "=== FACTORY RESET WITH RESTORE ==="
    
    if ! backup_config; then
        log_error "Backup failed, aborting"
        return 1
    fi
    
    echo
    log_warning "Backup created at: $BACKUP_FILE"
    log_warning "Download it before continuing!"
    echo "Use: scp root@$(uci get network.lan.ipaddr 2>/dev/null || echo 'ROUTER_IP'):$BACKUP_FILE ."
    echo
    
    read -p "Press Enter after downloading backup, or Ctrl+C to cancel..."
    
    log_info "Performing factory reset..."
    if factory_reset; then
        log_info "System will reboot. After reboot, run this script again to restore."
        exit 0
    fi
}

# ============================================================================
# MAIN MENU
# ============================================================================
show_menu() {
    clear
    echo "╔══════════════════════════════════════════════════╗"
    echo "║           OpenWRT Configuration Script           ║"
    echo "║           For Zapret on S1010 Router            ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "Available modes:"
    echo " 1) Full Install (update + configure)"
    echo " 2) Update Only (packages + Zapret + DNS)"
    echo " 3) Configure System (WiFi, network, time)"
    echo " 4) Update Zapret & Instagram DNS"
    echo " 5) Factory Reset with Restore"
    echo " 6) Backup Configuration"
    echo " 7) Restore Configuration"
    echo " 8) Update Packages Only"
    echo ""
    echo "Usage notes:"
    echo " - Modes 1 & 3 accept WiFi parameters:"
    echo "   $0 1 \"SSID-5G\" \"SSID-2.4G\" \"PASSWORD\""
    echo " - Log file: $LOG_FILE"
    echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    check_root
    mkdir -p "$TEMP_DIR"
    
    # Parse command line arguments
    if [ $# -ge 1 ]; then
        case "$1" in
            1) mode_full_install "$2" "$3" "$4" ;;
            2) mode_update_only ;;
            3) mode_configure "$2" "$3" "$4" ;;
            4) mode_zapret_dns ;;
            5) mode_factory_reset_restore ;;
            6) backup_config ;;
            7) restore_config ;;
            8) update_packages ;;
            *)
                log_error "Invalid mode: $1"
                show_menu
                exit 1
                ;;
        esac
        exit $?
    fi
    
    # Interactive mode
    show_menu
    
    read -p "Select mode (1-8): " choice
    case "$choice" in
        1) mode_full_install ;;
        2) mode_update_only ;;
        3) mode_configure ;;
        4) mode_zapret_dns ;;
        5) mode_factory_reset_restore ;;
        6) backup_config ;;
        7) restore_config ;;
        8) update_packages ;;
        *) log_error "Invalid choice"; exit 1 ;;
    esac
}

main "$@"