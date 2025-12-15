set -e

clear
echo "==============================================="
echo "        ARAIN CLOUD VM MANAGER – VPS CREATE     "
echo "==============================================="


[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }

export DEBIAN_FRONTEND=noninteractive


echo "[+] Updating & installing QEMU and utilities..."
apt-get update -y
apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils wget curl openssl


read -p "VPS Name: " VM_NAME
VM_NAME=${VM_NAME:-arain-$(date +%s)}

read -p "RAM MB [2048]: " VM_RAM
VM_RAM=${VM_RAM:-2048}

read -p "CPU Cores [2]: " VM_CPU
VM_CPU=${VM_CPU:-2}

read -p "Disk GB [20]: " VM_DISK
VM_DISK=${VM_DISK:-20}


echo "Select OS image:"
echo "1) Ubuntu 22.04 Jammy (default)"
echo "2) Debian 12 Bookworm"
read -p "Choice [1]: " OS_CHOICE
OS_CHOICE=${OS_CHOICE:-1}

if [ "$OS_CHOICE" -eq 2 ]; then
    IMG_URL="https://cloud.debian.org/images/cloud/bullseye/latest/debian-12-generic-amd64.qcow2"
    OS_NAME="Debian 12 Bookworm"
else
    IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    OS_NAME="Ubuntu 22.04 Jammy"
fi


VM_DIR="/opt/arain-vms"
IMG="$VM_DIR/$VM_NAME.qcow2"
SEED="$VM_DIR/$VM_NAME-seed.iso"

PASSWORD="$(openssl rand -base64 12)"
SSH_PORT="$(shuf -i 30000-60000 -n 1)"
HOST_IP="$(curl -4 -s ifconfig.me)"

mkdir -p "$VM_DIR"

echo "==============================================="
echo " VPS NAME : $VM_NAME"
echo " OS       : $OS_NAME"
echo " RAM      : $VM_RAM MB"
echo " CPU      : $VM_CPU"
echo " DISK     : $VM_DISK GB"
echo "==============================================="


if [ ! -f "$IMG" ]; then
    wget -O "$IMG" "$IMG_URL"
fi
qemu-img resize "$IMG" "${VM_DISK}G"
echo "Image resized."


cat > user-data <<EOF
#cloud-config
disable_root: false
ssh_pwauth: true

chpasswd:
  list: |
    root:$PASSWORD
  expire: false

packages:
  - curl

runcmd:
  # ---- SSH CONFIG ----
  - sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/^#\\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
  - sed -i 's/^#\\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
  - systemctl restart ssh

  # ---- SIMPLE MOTD ----
  - chmod -x /etc/update-motd.d/*
  - |
    cat << 'MOTD' > /etc/update-motd.d/00-arainnodes
    #!/bin/bash

    # Colors
    CYAN="\e[38;5;45m"
    GREEN="\e[38;5;82m"
    BLUE="\e[38;5;51m"
    RED="\e[38;5;196m"
    RESET="\e[0m"

    # ---- LOGO ----
    echo -e "${RED}"
    echo -e " █████╗ ██████╗  █████╗ ██╗███╗   ██╗"
    echo -e "██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║"
    echo -e "███████║██████╔╝███████║██║██╔██╗ ██║"
    echo -e "██╔══██║██╔══██╗██╔══██║██║██║╚██╗██║"
    echo -e "██║  ██║██║  ██║██║  ██║██║██║ ╚████║"
    echo -e "╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝"
    echo -e "${RESET}"

    # ---- WELCOME INFO ----
    echo -e "${GREEN} Welcome to Arain Cloud Datacenter 🚀 ${RESET}"
    echo -e "${CYAN}Support: support@arain.clloud${RESET}"
    echo -e "Website: ${BLUE}arain.cloud${RESET}"
    echo -e "${GREEN}Power • Performance • Stability 💪${RESET}"
    MOTD
    chmod +x /etc/update-motd.d/00-arainnodes
EOF

cat > meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

cloud-localds "$SEED" user-data meta-data

qemu-system-x86_64 \
-enable-kvm \
-m "$RAM" \
-smp "$CPU" \
-drive file="$VM_PATH.qcow2",format=qcow2,if=virtio \
-drive file="$VM_PATH-seed.iso",format=raw,if=virtio \
-netdev user,id=net0,hostfwd=tcp::$SSH_PORT-:22 \
-device virtio-net-pci,netdev=net0 \
-display none \
-daemonize


echo
echo "⏳ VPS is booting. Waiting 60 seconds..."
for i in {60..1}; do
    echo -ne "\r$i seconds remaining..."
    sleep 1
done
echo -e "\n✅ VPS should be ready now!"


echo
echo "🔐 SSH LOGIN:"
echo "ssh root@$HOST_IP -p $SSH_PORT"
echo "Password: $PASSWORD"
echo "==============================================="
