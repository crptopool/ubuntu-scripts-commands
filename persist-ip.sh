#!/bin/bash

# ============================================================
# Persistent Static IP Configuration for Ubuntu on ESXi
#
# Supported:
#   Ubuntu 20.04
#   Ubuntu 22.04
#   Ubuntu 24.04
#
# Purpose:
#   Convert the VM's CURRENT working IPv4 configuration
#   into a persistent Netplan static configuration.
# ============================================================

set -e

echo
echo "===================================================="
echo " Ubuntu ESXi VM - Persistent IP Configuration"
echo "===================================================="
echo

# ------------------------------------------------------------
# 1. Must run as root
# ------------------------------------------------------------

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run this script with sudo:"
    echo
    echo "    sudo bash $0"
    echo
    exit 1
fi


# ------------------------------------------------------------
# 2. Detect operating system
# ------------------------------------------------------------

if [ ! -f /etc/os-release ]; then
    echo "ERROR: Cannot detect operating system."
    exit 1
fi

source /etc/os-release

echo "Detected OS      : $PRETTY_NAME"
echo "Distribution     : $ID"
echo "Version          : $VERSION_ID"
echo

if [ "$ID" != "ubuntu" ]; then
    echo "ERROR: This script is intended only for Ubuntu."
    exit 1
fi


# ------------------------------------------------------------
# 3. Check supported Ubuntu versions
# ------------------------------------------------------------

case "$VERSION_ID" in

    "20.04")
        UBUNTU_VERSION="20.04"
        ;;

    "22.04")
        UBUNTU_VERSION="22.04"
        ;;

    "24.04")
        UBUNTU_VERSION="24.04"
        ;;

    *)
        echo "===================================================="
        echo "UNSUPPORTED UBUNTU VERSION"
        echo "===================================================="
        echo
        echo "Detected: Ubuntu $VERSION_ID"
        echo
        echo "Supported versions:"
        echo "  Ubuntu 20.04"
        echo "  Ubuntu 22.04"
        echo "  Ubuntu 24.04"
        echo
        echo "No network changes were made."
        exit 1
        ;;
esac

echo "Ubuntu $UBUNTU_VERSION is supported."
echo


# ------------------------------------------------------------
# 4. Check Netplan exists
# ------------------------------------------------------------

if ! command -v netplan >/dev/null 2>&1; then
    echo "ERROR: Netplan is not installed."
    echo "No changes made."
    exit 1
fi

NETPLAN_VERSION=$(netplan --version 2>/dev/null || echo "Installed")

echo "Netplan          : $NETPLAN_VERSION"
echo


# ------------------------------------------------------------
# 5. Detect primary network interface
# ------------------------------------------------------------

IFACE=$(ip -4 route show default | awk '{print $5; exit}')

if [ -z "$IFACE" ]; then
    echo "ERROR: Could not detect active network interface."
    exit 1
fi

echo "Interface        : $IFACE"


# ------------------------------------------------------------
# 6. Detect current IPv4 address
# ------------------------------------------------------------

IP_CIDR=$(ip -4 addr show dev "$IFACE" scope global \
          | awk '/inet / {print $2; exit}')

if [ -z "$IP_CIDR" ]; then
    echo "ERROR: Could not detect IPv4 address."
    exit 1
fi

IP_ADDR="${IP_CIDR%/*}"
PREFIX="${IP_CIDR#*/}"

echo "Current IP       : $IP_ADDR"
echo "Subnet Prefix    : /$PREFIX"


# ------------------------------------------------------------
# 7. Detect default gateway
# ------------------------------------------------------------

GATEWAY=$(ip -4 route show default | awk '{print $3; exit}')

if [ -z "$GATEWAY" ]; then
    echo "ERROR: Could not detect default gateway."
    exit 1
fi

echo "Gateway          : $GATEWAY"


# ------------------------------------------------------------
# 8. Detect MAC address
# ------------------------------------------------------------

MAC=$(cat "/sys/class/net/$IFACE/address")

if [ -z "$MAC" ]; then
    echo "ERROR: Could not detect MAC address."
    exit 1
fi

echo "MAC Address      : $MAC"


# ------------------------------------------------------------
# 9. Detect DNS servers
# ------------------------------------------------------------

DNS_LIST=""

# First try systemd-resolved
if command -v resolvectl >/dev/null 2>&1; then

    DNS_LIST=$(resolvectl dns "$IFACE" 2>/dev/null \
        | sed 's/.*: //' \
        | tr ' ' '\n' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
        | head -3 \
        | tr '\n' ',' \
        | sed 's/,$//')

fi


# Fallback to resolv.conf
if [ -z "$DNS_LIST" ]; then

    DNS_LIST=$(grep '^nameserver' /etc/resolv.conf 2>/dev/null \
        | awk '{print $2}' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
        | grep -v '^127\.' \
        | head -3 \
        | tr '\n' ',' \
        | sed 's/,$//')

fi


# Final fallback
if [ -z "$DNS_LIST" ]; then

    echo
    echo "WARNING: Could not detect usable DNS servers."
    echo "Using Cloudflare and Google DNS as fallback."
    DNS_LIST="1.1.1.1,8.8.8.8"

fi

DNS_YAML=$(echo "$DNS_LIST" | sed 's/,/, /g')

echo "DNS Servers      : $DNS_LIST"


# ------------------------------------------------------------
# 10. Display detected configuration
# ------------------------------------------------------------

echo
echo "===================================================="
echo " CURRENT CONFIGURATION"
echo "===================================================="

echo
echo "Ubuntu Version : $UBUNTU_VERSION"
echo "Interface      : $IFACE"
echo "IP Address     : $IP_CIDR"
echo "Gateway        : $GATEWAY"
echo "DNS            : $DNS_LIST"
echo "MAC Address    : $MAC"

echo
echo "===================================================="


# ------------------------------------------------------------
# 11. Verify gateway is reachable
# ------------------------------------------------------------

echo
echo "Checking gateway connectivity..."

if ping -c 2 -W 2 "$GATEWAY" >/dev/null 2>&1; then

    echo "Gateway $GATEWAY is reachable."

else

    echo
    echo "WARNING:"
    echo "Gateway $GATEWAY did not respond to ping."
    echo
    echo "The gateway may block ICMP, so this does not"
    echo "necessarily indicate a problem."
fi


# ------------------------------------------------------------
# 12. Create backup directory
# ------------------------------------------------------------

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

BACKUP_DIR="/root/netplan-backup-$TIMESTAMP"

mkdir -p "$BACKUP_DIR"

echo
echo "Backing up current Netplan configuration..."


# Backup YAML files
if ls /etc/netplan/*.yaml >/dev/null 2>&1; then

    cp -a /etc/netplan/*.yaml "$BACKUP_DIR/"

fi


# Backup cloud-init network config if present
if [ -f /etc/cloud/cloud.cfg.d/50-cloud-init.yaml ]; then

    cp -a /etc/cloud/cloud.cfg.d/50-cloud-init.yaml \
        "$BACKUP_DIR/" 2>/dev/null || true

fi

echo "Backup created:"
echo
echo "    $BACKUP_DIR"


# ------------------------------------------------------------
# 13. Disable cloud-init NETWORK management
# ------------------------------------------------------------

if [ -d /etc/cloud ]; then

    echo
    echo "Cloud-init detected."

    mkdir -p /etc/cloud/cloud.cfg.d

    cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<EOF
network:
  config: disabled
EOF

    echo "Cloud-init network management disabled."

else

    echo
    echo "Cloud-init not detected."
    echo "Skipping cloud-init configuration."

fi


# ------------------------------------------------------------
# 14. Move existing Netplan configs
# ------------------------------------------------------------

OLD_DIR="/etc/netplan/backup-before-static-$TIMESTAMP"

mkdir -p "$OLD_DIR"

for FILE in /etc/netplan/*.yaml; do

    [ -e "$FILE" ] || continue

    mv "$FILE" "$OLD_DIR/"

done


# ------------------------------------------------------------
# 15. Write new persistent configuration
# ------------------------------------------------------------

NETPLAN_FILE="/etc/netplan/01-static-ip.yaml"

cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd

  ethernets:

    $IFACE:

      match:
        macaddress: "$MAC"

      set-name: "$IFACE"

      dhcp4: false
      dhcp6: false

      addresses:
        - $IP_CIDR

      routes:
        - to: default
          via: $GATEWAY

      nameservers:
        addresses: [$DNS_YAML]
EOF


chmod 600 "$NETPLAN_FILE"


# ------------------------------------------------------------
# 16. Display generated configuration
# ------------------------------------------------------------

echo
echo "===================================================="
echo " NEW PERSISTENT CONFIGURATION"
echo "===================================================="
echo

cat "$NETPLAN_FILE"

echo
echo "===================================================="


# ------------------------------------------------------------
# 17. Validate Netplan
# ------------------------------------------------------------

echo
echo "Validating configuration..."

if netplan generate; then

    echo
    echo "SUCCESS: Netplan configuration is valid."

else

    echo
    echo "===================================================="
    echo "ERROR: NETPLAN VALIDATION FAILED"
    echo "===================================================="

    echo
    echo "Restoring previous configuration..."

    rm -f "$NETPLAN_FILE"

    cp -a "$BACKUP_DIR"/*.yaml /etc/netplan/ 2>/dev/null || true

    echo
    echo "Previous configuration restored."
    echo
    echo "NO NETWORK CHANGES WERE APPLIED."

    exit 1

fi


# ------------------------------------------------------------
# 18. Instructions
# ------------------------------------------------------------

echo
echo "===================================================="
echo " CONFIGURATION READY"
echo "===================================================="
echo
echo "NO NETWORK CHANGE HAS BEEN APPLIED YET."
echo
echo "Current SSH connection should therefore still work."
echo
echo "To safely test the configuration run:"
echo
echo "    sudo netplan try"
echo
echo "Netplan will apply the configuration temporarily."
echo
echo "If your SSH/network connection still works,"
echo "accept the configuration."
echo
echo
echo "Then verify:"
echo
echo "    ip addr show $IFACE"
echo "    ip route"
echo "    resolvectl status"
echo
echo "Finally reboot:"
echo
echo "    sudo reboot"
echo
echo "After reboot check:"
echo
echo "    hostname -I"
echo
echo "Expected IP:"
echo
echo "    $IP_ADDR"
echo
echo "Backup location:"
echo
echo "    $BACKUP_DIR"
echo
echo "===================================================="
