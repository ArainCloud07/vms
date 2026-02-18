#!/bin/bash
set -e

# ==================================================
#   ARYN CLOUD VM MANAGER – FULL VERSION
#   Create | Start | Stop | Delete | Auto-Start
# ==================================================

VM_DIR="/opt/aryn-vms"
SERVICE_DIR="/etc/systemd/system"

# ---- ROOT CHECK ----
[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
mkdir -p "$VM_DIR"

# ---- FUNCTIONS ----
list_vms() {
  ls "$VM_DIR"/*.qcow2 2>/dev/null | sed 's#.*/##;s#.qcow2##' || echo "No VPS found"
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

ExecStop=/usr/bin/pkill -f "qemu-system-x86_64.*$IMG"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable aryn-$VM_NAME
}

# ---- MENU LOOP ----
while true; do
  clear
  echo "==============================================="
  echo "        ARYN CLOUD VM MANAGER – VPS CONTROL    "
  echo "==============================================="
  echo
  echo "1) Create VPS"
  echo "2) Start VPS"
  echo "3) Stop VPS"
  echo "4) Delete VPS"
  echo "5) List VPS"
  echo "0) Exit"
  read -p "Select option [0-5]: " ACTION

  case "$ACTION" in
  # ================= CREATE VPS =================
  1)
    clear
    echo "[+] Installing dependencies..."
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

    echo "1) Ubuntu 22.04 Jammy"
    echo "2) Debian 12 Bookworm"
    read -p "OS Choice [1]: " OS_CHOICE
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

    echo "[+] Downloading OS image..."
    wget -O "$IMG" "$IMG_URL"
    qemu-img resize "$IMG" "${VM_DISK}G"

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
    cat << 'MOTD' > /etc/update-motd.d/00-aryn
    #!/bin/bash
    echo ""
    echo " █████╗ ██████╗ ██╗   ██╗███╗   ██╗"
    echo "██╔══██╗██╔══██╗╚██╗ ██╔╝████╗  ██║"
    echo "███████║██████╔╝ ╚████╔╝ ██╔██╗ ██║"
    echo "██╔══██║██╔══██╗  ╚██╔╝  ██║╚██╗██║"
    echo "██║  ██║██║  ██║   ██║   ██║ ╚████║"
    echo "╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═══╝"
    echo ""
    echo " 🚀 Welcome to Aryn Cloud Datacenter"
    echo " 🌐 Website : https://aryncloud.in"
    echo " 📧 Support : support@aryncloud.in"
    echo " 🖥 VPS Private IP : \$(hostname -I | awk '{print \$1}')"
    echo ""
    MOTD
  - chmod +x /etc/update-motd.d/00-aryn
EOF

    cat > meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

    cloud-localds "$SEED" user-data meta-data

    create_service
    systemctl start aryn-$VM_NAME

    echo
    echo "⏳ VPS is booting. Waiting 60 seconds..."
    for i in {60..1}; do
      echo -ne "\r$i seconds remaining..."
      sleep 1
    done
    echo -e "\n✅ VPS should be ready now!"

    echo "==============================================="
    echo " VPS CREATED SUCCESSFULLY "
    echo " Name     : $VM_NAME"
    echo " OS       : $OS_NAME"
    echo " SSH CMD  : ssh root@$HOST_IP -p $SSH_PORT"
    echo " Password : $PASSWORD"
    echo "==============================================="
    echo "[+] VPS creation complete. Exiting script."
    exit 0
    ;;

  # ================= START VPS =================
  2)
    clear
    echo "Available VPS:"; list_vms
    read -p "VPS Name: " VM_NAME
    systemctl start aryn-$VM_NAME
    echo "VPS $VM_NAME started"
    read -p "Press Enter to return to the menu..."
    ;;

  # ================= STOP VPS =================
  3)
    clear
    echo "Available VPS:"; list_vms
    read -p "VPS Name: " VM_NAME
    systemctl stop aryn-$VM_NAME
    echo "VPS $VM_NAME stopped"
    read -p "Press Enter to return to the menu..."
    ;;

  # ================= DELETE VPS =================
  4)
    clear
    echo "Available VPS:"; list_vms
    read -p "VPS Name to DELETE: " VM_NAME
    systemctl stop aryn-$VM_NAME || true
    systemctl disable aryn-$VM_NAME || true
    rm -f "$SERVICE_DIR/aryn-$VM_NAME.service"
    rm -f "$VM_DIR/$VM_NAME.qcow2" "$VM_DIR/$VM_NAME-seed.iso"
    systemctl daemon-reload
    echo "VPS $VM_NAME deleted completely"
    read -p "Press Enter to return to the menu..."
    ;;

  # ================= LIST VPS =================
  5)
    clear
    echo "==============================================="
    echo " VPS LIST (Name | Status | SSH Port)"
    echo "==============================================="
    for img in "$VM_DIR"/*.qcow2; do
      [ -e "$img" ] || { echo "No VPS found"; break; }
      VM_NAME=$(basename "$img" .qcow2)
      if systemctl is-active --quiet aryn-$VM_NAME; then
        STATUS="RUNNING"
      else
        STATUS="STOPPED"
      fi
      PORT=$(grep -o "hostfwd=tcp::[0-9]*" "$SERVICE_DIR/aryn-$VM_NAME.service" 2>/dev/null | cut -d: -f4)
      printf "%-20s | %-8s | %s\n" "$VM_NAME" "$STATUS" "$PORT"
    done
    echo "==============================================="
    read -p "Press Enter to return to the menu..."
    ;;

  0)
    echo "Exiting..."
    exit 0
    ;;

  *)
    echo "Invalid option"
    read -p "Press Enter to return to the menu..."
    ;;
  esac
done
