
set -e

VM_DIR="/opt/arain-vms"
SERVICE_DIR="/etc/systemd/system"
FW_DB="$VM_DIR/forwards.db"
REMOTE_HOST="86.96.192.78"
REMOTE_USER="root"
SSH_PORT_DEFAULT="65535"
LOCAL_SHOW_IP="127.0.0.1"

mkdir -p "$VM_DIR"
touch "$FW_DB"

[ "$EUID" -ne 0 ] && { echo "Run as root"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_WHITE='\033[1;37m'

pause_menu() {
    echo ""
    read -p "Press Enter to return to the menu..."
}

show_menu() {
clear
echo "==============================================="
echo " Arain Cloud VM Manager And Tunneling Tool v5"
echo "==============================================="
echo "1) Create VPS"
echo "2) Start VPS"
echo "3) Stop VPS"
echo "4) Delete VPS"
echo "5) List VPS"
echo "6) Add Tunnel"
echo "7) List Tunnels"
echo "8) Delete Tunnel"
echo "0) Exit"
read -p "Select option [0-8]: " ACTION
}

list_vms() {
echo "==============================================="
echo "Available VPS:"
for f in "$VM_DIR"/*.qcow2; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .qcow2)
    status=$(systemctl is-active "arain-$name" 2>/dev/null || echo inactive)
    echo -e "VPS: ${C_CYAN}$name${C_RESET} | Status: ${C_GREEN}$status${C_RESET}"
done
}

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

systemctl daemon-reload >/dev/null 2>&1
systemctl enable arain-$VM_NAME >/dev/null 2>&1
}


while true; do
show_menu

case "$ACTION" in

1)
apt-get update -y >/dev/null
apt-get install -y qemu-system-x86 qemu-utils cloud-image-utils wget curl openssl >/dev/null

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

wget -q -O "$IMG" "$IMG_URL"
qemu-img resize "$IMG" "${VM_DISK}G"

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
 - systemctl restart ssh || systemctl restart sshd
 - chmod -x /etc/update-motd.d/*
 - |
   cat << 'MOTD' > /etc/update-motd.d/00-arain
#!/bin/bash
clear
echo ""
echo " █████╗ ██████╗  █████╗ ██╗███╗   ██╗"
echo "██╔══██╗██╔══██╗██╔══██╗██║████╗  ██║"
echo "███████║██████╔╝███████║██║██╔██╗ ██║"
echo "██╔══██║██╔══██╗██╔══██║██║██║╚██╗██║"
echo "██║  ██║██║  ██║██║  ██║██║██║ ╚████║"
echo "╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝"
echo ""
echo " 🚀 Welcome to Arain Cloud Datacenter"
echo " 🌐 Website : https://arain.cloud"
echo " 📧 Support : support@arain.cloud"
echo " 🖥 VPS Private IP : \$(hostname -I | awk '{print \$1}')"
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
systemctl start arain-$VM_NAME >/dev/null 2>&1

echo -e "\n==============================================="
echo " VPS CREATED SUCCESSFULLY "
echo " Name     : $VM_NAME"
echo " OS       : $OS_NAME"
echo " SSH CMD  : ssh root@$HOST_IP -p $SSH_PORT"
echo " Password : $PASSWORD"
echo " Public IP: $HOST_IP"
echo "==============================================="


exit 0
;;

2) list_vms; read -p "VPS Name: " V; systemctl start arain-$V >/dev/null 2>&1; pause_menu ;;
3) list_vms; read -p "VPS Name: " V; systemctl stop arain-$V >/dev/null 2>&1; pause_menu ;;
4) list_vms; read -p "VPS Name: " V; systemctl stop arain-$V >/dev/null 2>&1; rm -f "$VM_DIR/$V.qcow2" "$VM_DIR/$V-seed.iso" "$SERVICE_DIR/arain-$V.service"; systemctl daemon-reload >/dev/null 2>&1; pause_menu ;;
5) list_vms; pause_menu ;;

6)
read -p "Local Port to expose: " LOCAL_PORT
read -p "Remote Port on tunnel host: " REMOTE_PORT

SERVICE_NAME="tunnel-${REMOTE_PORT}.service"
SERVICE_FILE="${SERVICE_DIR}/${SERVICE_NAME}"

if [[ -f "$SERVICE_FILE" ]]; then
    echo "Tunnel already exists"
    pause_menu
    continue
fi

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=SSH Tunnel ${REMOTE_PORT}
After=network-online.target

[Service]
ExecStart=/usr/bin/ssh -N \\
-o ExitOnForwardFailure=yes \\
-o ServerAliveInterval=30 \\
-o ServerAliveCountMax=3 \\
-o StrictHostKeyChecking=no \\
-R ${REMOTE_PORT}:localhost:${LOCAL_PORT} \\
${REMOTE_USER}@${REMOTE_HOST} -p ${SSH_PORT_DEFAULT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >/dev/null 2>&1
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
systemctl start "$SERVICE_NAME" >/dev/null 2>&1

echo "Tunnel created & persistent"
echo "Local  : ${LOCAL_SHOW_IP}:${LOCAL_PORT}"
echo "Remote : ${REMOTE_HOST}:${REMOTE_PORT}"
pause_menu
;;

7)
echo "==============================================="
echo "Active tunnels:"
found=0
for s in ${SERVICE_DIR}/tunnel-*.service; do
    [ -e "$s" ] || continue
    found=1
    port=$(basename "$s" | sed 's/tunnel-//;s/.service//')
    status=$(systemctl is-active tunnel-$port)
    echo -e "Remote ${C_CYAN}${REMOTE_HOST}:${port}${C_RESET} → Local ${LOCAL_SHOW_IP}:${port} → ${status}"
done

if [ $found -eq 0 ]; then
    echo "No tunnels found"
fi

pause_menu
;;

0)
echo "Bye 👋 Exiting Arain Cloud Manager"
exit 0
;;

8)
echo "Existing tunnels:"
for s in ${SERVICE_DIR}/tunnel-*.service; do
    [ -e "$s" ] || { echo "No tunnels found"; pause_menu; break; }
    echo " - $(basename "$s" | sed 's/tunnel-//;s/.service//')"
done
read -p "Remote Port to delete: " DP
systemctl stop tunnel-$DP >/dev/null 2>&1 || true
systemctl disable tunnel-$DP >/dev/null 2>&1 || true
rm -f "${SERVICE_DIR}/tunnel-$DP.service"
systemctl daemon-reload >/dev/null 2>&1
echo "Tunnel removed"
pause_menu
;;

*)
echo "Invalid option"
pause_menu
;;
esac
done
