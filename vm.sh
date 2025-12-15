#!/bin/bash
set -e

clear
echo "==============================================="
echo "        ARAIN CLOUD VM MANAGER – VPS CREATE     "
echo "==============================================="

# ---- ROOT CHECK ----
[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

# ---- INSTALL DEPENDENCIES ----
echo "[+] Updating & installing QEMU and utilities..."
apt-get update -y
apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils wget curl openssl

# ---- INPUT ----
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
    IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
    OS_NAME="Debian 12 Bookworm"
else
    IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    OS_NAME="Ubuntu 22.04 Jammy"
fi

# ---- VARS ----
VM_DIR="/opt/arain-vms"
VM_PATH="${VM_DIR}/${VM_NAME}"
IMG="${VM_PATH}.qcow2"
SEED="${VM_PATH}-seed.iso"

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

# ---- IMAGE ----
if [ ! -f "$IMG" ]; then
    wget -O "$IMG" "$IMG_URL"
fi

qemu-img resize "$IMG" "${VM_DISK}G"
echo "Image resized."

# ---- CLOUD INIT ----
cat > user-data <<EOF
#cloud-config
disable_root: false
ssh_pwauth: true

chpasswd:
  list: |
    root:$PASSWORD
  expire: false

runcmd:
  - sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - systemctl restart ssh

  - chmod -x /etc/update-motd.d/*
  - |
    cat << 'MOTD' > /etc/update-motd.d/00-arainnodes
    #!/bin/bash
    echo ""
    echo " █████╗ ██████╗  █████╗ ██╗███╗   ██╗"
    echo "██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║"
    echo "███████║██████╔╝███████║██║██╔██╗ ██║"
    echo "██╔══██║██╔══██╗██╔══██║██║██║╚██╗██║"
    echo "██║  ██║██║  ██║██║  ██║██║██║ ╚████║"
    echo "╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝"
    echo ""
    echo " Welcome to Arain Cloud Datacenter 🚀"
    echo " Website: arain.cloud"
    echo " Support: support@arain.cloud"
    echo ""
    MOTD
    chmod +x /etc/update-motd.d/00-arainnodes
EOF

cat > meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

cloud-localds "$SEED" user-data meta-data

# ---- START VM (NO GTK, NO CUT) ----
# QEMU start
qemu-system-x86_64 \
-enable-kvm \
-m "$VM_RAM" \
-smp "$VM_CPU" \
-cpu host \
-drive file="$IMG",format=qcow2,if=virtio \
-drive file="$SEED",format=raw,if=virtio \
-netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
-device virtio-net-pci,netdev=net0 \
-display none \
-daemonize



# ---- WAIT ----
echo
echo "⏳ VPS is booting. Waiting 60 seconds..."
sleep 60
echo "✅ VPS should be ready now!"

# ---- FINAL ----
echo
echo "🔐 SSH LOGIN:"
echo "ssh root@$HOST_IP -p $SSH_PORT"
echo "Password: $PASSWORD"
echo "==============================================="
