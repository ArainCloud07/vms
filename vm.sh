#!/bin/bash
set -e

# ==================================================
#   ARYN CLOUD VM MANAGER – FULL VERSION
# ==================================================

VM_DIR="/opt/aryn-vms"
SERVICE_DIR="/etc/systemd/system"

[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
mkdir -p "$VM_DIR"

list_vms() {
  find "$VM_DIR" -name "*.qcow2" -exec basename {} .qcow2 \; 2>/dev/null || echo "No VPS found"
}

create_service() {
cat > "$SERVICE_DIR/aryn-$VM_NAME.service" <<EOF
[Unit]
Description=Aryn Cloud VPS $VM_NAME
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/qemu-system-x86_64 \\
  -enable-kvm \\
  -m $VM_RAM \\
  -smp $VM_CPU \\
  -cpu host \\
  -drive file=$IMG,format=qcow2,if=virtio \\
  -drive file=$SEED,format=raw,if=virtio \\
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \\
  -device virtio-net-pci,netdev=net0 \\
  -display none \\
  -daemonize

ExecStop=/usr/bin/pkill -f "$IMG"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable aryn-$VM_NAME
}

while true; do
  clear
  echo "==============================================="
  echo "        ARYN CLOUD VM MANAGER"
  echo "==============================================="
  echo "1) Create VPS"
  echo "2) Start VPS"
  echo "3) Stop VPS"
  echo "4) Delete VPS"
  echo "5) List VPS"
  echo "0) Exit"
  read -p "Select option: " ACTION

  case "$ACTION" in

  1)
    apt-get update -y
    apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils wget curl openssl

    read -p "VPS Name: " VM_NAME
    VM_NAME=${VM_NAME:-vm-$(date +%s)}

    read -p "RAM MB [2048]: " VM_RAM
    VM_RAM=${VM_RAM:-2048}

    read -p "CPU Cores [2]: " VM_CPU
    VM_CPU=${VM_CPU:-2}

    read -p "Disk GB [20]: " VM_DISK
    VM_DISK=${VM_DISK:-20}

    echo "1) Ubuntu 22.04"
    echo "2) Debian 12"
    read -p "Choice [1]: " OS_CHOICE
    OS_CHOICE=${OS_CHOICE:-1}

    if [ "$OS_CHOICE" -eq 2 ]; then
      IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
      OS_NAME="Debian 12"
    else
      IMG_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
      OS_NAME="Ubuntu 22.04"
    fi

    IMG="$VM_DIR/$VM_NAME.qcow2"
    SEED="$VM_DIR/$VM_NAME-seed.iso"

    PASSWORD="$(openssl rand -base64 12)"
    SSH_PORT="$(shuf -i 30000-60000 -n 1)"
    HOST_IP="$(curl -4 -s ifconfig.me)"

    wget -O "$IMG" "$IMG_URL"
    qemu-img resize "$IMG" "${VM_DISK}G"

cat > user-data <<EOF
#cloud-config
disable_root: false
ssh_pwauth: true
chpasswd:
  list: |
    root:$PASSWORD
  expire: false
EOF

cat > meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

    cloud-localds "$SEED" user-data meta-data

    create_service
    systemctl start aryn-$VM_NAME

    echo
    echo "VPS CREATED"
    echo "Name: $VM_NAME"
    echo "SSH: ssh root@$HOST_IP -p $SSH_PORT"
    echo "Password: $PASSWORD"
    read -p "Press Enter..."
    ;;

  2)
    list_vms
    read -p "VPS Name: " VM_NAME
    systemctl start aryn-$VM_NAME
    ;;

  3)
    list_vms
    read -p "VPS Name: " VM_NAME
    systemctl stop aryn-$VM_NAME
    ;;

  4)
    list_vms
    read -p "Delete VPS: " VM_NAME
    systemctl stop aryn-$VM_NAME 2>/dev/null || true
    systemctl disable aryn-$VM_NAME 2>/dev/null || true
    rm -f "$SERVICE_DIR/aryn-$VM_NAME.service"
    rm -f "$VM_DIR/$VM_NAME.qcow2" "$VM_DIR/$VM_NAME-seed.iso"
    systemctl daemon-reload
    echo "Deleted."
    read -p "Press Enter..."
    ;;

  5)
    for img in "$VM_DIR"/*.qcow2; do
      [ -e "$img" ] || { echo "No VPS found"; break; }
      VM_NAME=$(basename "$img" .qcow2)
      systemctl is-active --quiet aryn-$VM_NAME && STATUS="RUNNING" || STATUS="STOPPED"
      echo "$VM_NAME  |  $STATUS"
    done
    read -p "Press Enter..."
    ;;

  0)
    exit 0
    ;;
  esac
done
