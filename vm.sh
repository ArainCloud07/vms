#!/bin/bash
set -e

# ==================================================
#   ARAIN CLOUD VPS MANAGER – FINAL FULL VERSION
# ==================================================

VM_DIR="/opt/arain-vms"
SERVICE_DIR="/etc/systemd/system"
TUNNEL_FILE="/opt/arain-vms/tunnels.db"

mkdir -p "$VM_DIR"
touch "$TUNNEL_FILE"

clear
echo "==============================================="
echo "        ARAIN CLOUD VM MANAGER – FINAL          "
echo "==============================================="

# ---- ROOT CHECK ----
[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

# ==================================================
list_vms() {
  ls "$VM_DIR"/*.qcow2 2>/dev/null | sed 's#.*/##;s#.qcow2##' || echo "No VPS found"
}

# ==================================================
create_service() {
cat > "$SERVICE_DIR/arain-$VM_NAME.service" <<EOF
[Unit]
Description=Arain Cloud VPS $VM_NAME
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
systemctl enable arain-$VM_NAME
}

# ==================================================
echo "1) Create VPS"
echo "2) Start VPS"
echo "3) Stop VPS"
echo "4) Delete VPS"
echo "5) List VPS"
echo "6) Create Tunnel"
echo "7) List Tunnels"
echo "8) Delete Tunnel"
echo "9) Delete ALL Tunnels"
read -p "Select option [1-9]: " ACTION

case "$ACTION" in

# ================= CREATE VPS =================
1)
  apt-get update -y
  apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils wget curl openssl

  read -p "VPS Name: " VM_NAME
  read -p "RAM MB [2048]: " VM_RAM
  read -p "CPU Cores [2]: " VM_CPU
  read -p "Disk GB [20]: " VM_DISK

  VM_RAM=${VM_RAM:-2048}
  VM_CPU=${VM_CPU:-2}
  VM_DISK=${VM_DISK:-20}

  echo "1) Ubuntu 22.04"
  echo "2) Debian 12"
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

  wget -O "$IMG" "$IMG_URL"
  qemu-img resize "$IMG" "${VM_DISK}G"

# ---------- CLOUD INIT ----------
cat > user-data <<EOF
#cloud-config
disable_root: false
ssh_pwauth: true
chpasswd:
  list: |
    root:$PASSWORD
  expire: false

runcmd:
  - sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  - sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  - systemctl restart ssh || systemctl restart sshd

  - chmod -x /etc/update-motd.d/*
  - |
    cat << 'MOTD' > /etc/update-motd.d/00-arain
    #!/bin/bash
    echo ""
    echo " █████╗ ██████╗  █████╗ ██╗███╗   ██╗"
    echo "██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║"
    echo "███████║██████╔╝███████║██║██╔██╗ ██║"
    echo "██╔══██║██╔══██╗██╔══██║██║██║╚██╗██║"
    echo "██║  ██║██║  ██║██║  ██║██║██║ ╚████║"
    echo "╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝"
    echo ""
    echo " 🚀 Welcome to Arain Cloud Datacenter"
    echo " 🌐 https://arain.cloud"
    echo " 📧 support@arain.cloud"
    echo ""
    MOTD
  - chmod +x /etc/update-motd.d/00-arain
EOF

cat > meta-data <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

cloud-localds "$SEED" user-data meta-data
create_service
systemctl start arain-$VM_NAME

echo "⏳ VPS booting... waiting 60 seconds"
for i in {60..1}; do echo -ne "\r$i seconds remaining"; sleep 1; done
echo -e " ✅ VPS should be ready now!"
echo -e "\n==============================================="
echo " VPS CREATED SUCCESSFULLY "
echo " Name     : $VM_NAME"
echo " OS       : $OS_NAME"
echo " SSH CMD  : ssh root@$HOST_IP -p $SSH_PORT"
echo " Password : $PASSWORD"
echo "==============================================="
;;

# ================= START =================
2) list_vms; read -p "VPS Name: " VM_NAME; systemctl start arain-$VM_NAME ;;
3) list_vms; read -p "VPS Name: " VM_NAME; systemctl stop arain-$VM_NAME ;;
4) list_vms; read -p "VPS Name: " VM_NAME;
   systemctl stop arain-$VM_NAME || true
   systemctl disable arain-$VM_NAME || true
   rm -f "$SERVICE_DIR/arain-$VM_NAME.service" "$VM_DIR/$VM_NAME.qcow2" "$VM_DIR/$VM_NAME-seed.iso"
   systemctl daemon-reload ;;
5) list_vms ;;

# ================= TUNNELS =================
6) read -p "Local Port: " LP; read -p "Remote Port: " RP;
   ssh -fN -R ${RP}:localhost:${LP} root@localhost
   echo "$LP:$RP" >> "$TUNNEL_FILE"
   echo "Tunnel created $LP -> $RP" ;;

7) cat "$TUNNEL_FILE" ;;
8) read -p "Remote Port: " RP;
   pkill -f "R ${RP}"
   sed -i "/:$RP/d" "$TUNNEL_FILE" ;;
9) pkill ssh || true; > "$TUNNEL_FILE" ;;

*) echo "Invalid option" ;;
esac
