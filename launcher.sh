#!/bin/bash

###############################################################################
# VirtCrafter Core - Open Source Edition
# Single-VM Rocky Linux 9.6 Unattended Installer
# GPL v3.0 — Free for personal and commercial use
# https://github.com/ahmadmwaddah/virt-crafter-core
###############################################################################

set -Euo pipefail

# ========================
# CONFIGURATION (HARDCODED)
# ========================
readonly VM_NAME="virt-crafter-vm"
readonly RAM="3072"
readonly VCPUS="2"
readonly DISK="30"
readonly TIMEZONE="Africa/Cairo"
readonly USERNAME="ops"
readonly USER_PASSWORD="159Zxc753"
readonly ROOT_PASSWORD="159Zxc753#"
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ISO_PATH="$PROJECT_ROOT/iso/Rocky-9.6-x86_64-minimal.iso"
readonly TEMPLATE_PATH="$PROJECT_ROOT/templates/rocky-ks.cfg.template"
readonly IMAGE_DIR="$HOME/virt-crafter-core/vms"
readonly LOG_DIR="$HOME/virt-crafter-core/logs"
readonly HTTP_PORT=8080
readonly ROCKY_OS_VARIANT="rocky9"

# Ensure logs directory exists
mkdir -p "$LOG_DIR"

# ========================
# LOGGING
# ========================
log_info() { echo -e "\033[0;36m🔧 $1\033[0m"; }
log_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
log_error() { echo -e "\033[0;31m❌ $1\033[0m"; }
log_cyan() { echo -e "\033[0;36m$1\033[0m"; }
log_warn() { echo -e "\033[1;33m⚠️  $1\033[0m"; }

# ========================
# DIRECTORY SETUP
# ========================
ensure_directories() {
    log_info "Creating required directories..."
    mkdir -p "$HOME/virt-crafter-core/iso"
    mkdir -p "$IMAGE_DIR"
    mkdir -p "$LOG_DIR"
    log_success "Directories ready"
}

# ========================
# DEPENDENCY CHECK
# ========================
check_dependencies() {
    log_info "Checking system dependencies..."
    local deps=("virsh" "qemu-img" "curl" "sed" "awk" "grep" "python3")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        log_error "Install with: sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virtinst curl python3"
        exit 1
    fi

    # Check KVM
    if ! grep -q -E "(vmx|svm)" /proc/cpuinfo; then
        log_warn "CPU virtualization not detected. VMs may run slowly."
    fi

    # Check libvirt permissions
    if ! virsh list --all &> /dev/null; then
        log_error "Permission denied: Add user to libvirt and kvm groups"
        log_error "Run: sudo usermod -a -G libvirt,kvm \$USER && newgrp libvirt"
        exit 1
    fi

    log_success "All dependencies satisfied"
}

# ========================
# VERIFY ISO EXISTS
# ========================
verify_iso() {
    if [[ ! -f "$ISO_PATH" ]]; then
        log_error "ISO file not found: $ISO_PATH"
        log_error "Please download Rocky Linux 9.6 Minimal ISO and place it here:"
        log_error "https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.6-x86_64-minimal.iso"
        exit 1
    fi
    log_success "ISO found: $(basename "$ISO_PATH")"
}

# ========================
# START HTTP SERVER FOR KICKSTART
# ========================
start_ks_server() {
    local serve_dir="$1"
    local port=$HTTP_PORT

    log_info "Starting HTTP server on port $port..."

    # Kill any existing server
    if pid=$(lsof -t -i :$port -sTCP:LISTEN 2>/dev/null); then
        kill -TERM "$pid" 2>/dev/null
        sleep 2
        kill -9 "$pid" 2>/dev/null || true
    fi

    cd "$serve_dir" && python3 -m http.server "$port" --bind 0.0.0.0 > /dev/null 2>&1 &
    KS_PID=$!
    echo "$KS_PID" > "$IMAGE_DIR/http_server.pid"

    sleep 2

    if ! ps -p "$KS_PID" > /dev/null 2>&1; then
        log_error "HTTP server failed to start"
        return 1
    fi

    # Test server
    local test_file="$serve_dir/test_http.txt"
    echo "test" > "$test_file"

    local attempt=1
    while [[ $attempt -le 10 ]]; do
        if curl -s --connect-timeout 2 "http://127.0.0.1:$port/test_http.txt" > /dev/null; then
            rm -f "$test_file"
            log_success "HTTP server running on http://0.0.0.0:$port"
            return 0
        fi
        sleep 1
        ((attempt++))
    done

    log_error "HTTP server not responding"
    kill "$KS_PID" 2>/dev/null || true
    rm -f "$test_file"
    return 1
}

# ========================
# DETECT HOST IP FOR HTTP SERVER
# ========================
detect_host_ip() {
    local detected_ip=""
    
    if ip route get 192.168.122.1 >/dev/null 2>&1; then
        detected_ip="192.168.122.1"
    elif ip addr show virbr0 >/dev/null 2>&1; then
        detected_ip=$(ip addr show virbr0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
    else
        detected_ip=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+' | head -1)
    fi
    
    echo "$detected_ip"
}

# ========================
# CONFIGURE FIREWALL
# ========================
configure_firewall() {
    log_info "Configuring firewall for port $HTTP_PORT..."
    if command -v firewall-cmd &> /dev/null; then
        sudo firewall-cmd --permanent --add-port=$HTTP_PORT/tcp >/dev/null 2>&1 || true
        sudo firewall-cmd --reload >/dev/null 2>&1 || true
    elif command -v ufw &> /dev/null; then
        sudo ufw allow $HTTP_PORT/tcp >/dev/null 2>&1 || true
        sudo ufw reload >/dev/null 2>&1 || true
    else
        log_warn "No supported firewall detected"
    fi
}

# ========================
# SETUP LIBVIRT NETWORK
# ========================
setup_network() {
    log_info "Configuring libvirt network..."

    if virsh net-info default 2>/dev/null | grep -q "Active.*yes"; then
        log_success "Default network is active"
        return 0
    fi

    if virsh net-info default 2>/dev/null; then
        log_warn "Default network exists — starting it..."
        sudo virsh net-start default
        log_success "Default network started"
        return 0
    fi

    log_warn "Creating default libvirt network..."
    sudo virsh net-define /dev/stdin <<EOF
<network>
  <name>default</name>
  <uuid>$(uuidgen)</uuid>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF

    sudo virsh net-autostart default
    sudo virsh net-start default
    log_success "Default network created and started"
}

# ========================
# GENERATE KICKSTART FILE
# ========================
generate_kickstart() {
    local ks_file="$IMAGE_DIR/ks_$VM_NAME.cfg"
    log_info "Generating kickstart file: $ks_file"

    # Copy template and replace placeholders
    cp "$TEMPLATE_PATH" "$ks_file" || { log_error "Failed to copy template"; exit 1; }

    # Replace placeholders with hardcoded values
    sed -i "s|{{HOSTNAME}}|$VM_NAME|g" "$ks_file"
    sed -i "s|{{USERNAME}}|$USERNAME|g" "$ks_file"
    sed -i "s|{{TIMEZONE}}|$TIMEZONE|g" "$ks_file"

    log_success "Kickstart file generated"
}

# ========================
# CREATE VM WITH WORKING METHOD
# ========================
install_vm() {
    local disk_path="$IMAGE_DIR/$VM_NAME.qcow2"

    if virsh dominfo "$VM_NAME" &> /dev/null; then
        log_warn "Found existing VM '$VM_NAME' — undefining it..."
        virsh undefine "$VM_NAME" --remove-all-storage
    fi

    if [[ -f "$disk_path" ]]; then
        log_warn "Found existing disk image — deleting it..."
        rm -f "$disk_path"
    fi

    log_info "Creating disk image: $disk_path ($DISK GB)"
    qemu-img create -f qcow2 -q "$disk_path" "${DISK}G" || { log_error "Failed to create disk"; exit 1; }

    setup_network

    configure_firewall

    HOST_IP=$(detect_host_ip)
    if [[ -z "$HOST_IP" ]]; then
        log_error "Could not detect host IP"
        exit 1
    fi
    log_success "Detected host IP: $HOST_IP"

    generate_kickstart

    if ! start_ks_server "$IMAGE_DIR"; then
        log_error "Failed to start HTTP server"
        exit 1
    fi

    log_info "Starting VM installation..."
    log_cyan "   VM Name: $VM_NAME"
    log_cyan "   RAM: $RAM MB"
    log_cyan "   vCPUs: $VCPUS"
    log_cyan "   Disk: $DISK GB"
    log_cyan "   Timezone: $TIMEZONE"
    log_cyan "   Username: $USERNAME"
    log_cyan "   Password: $USER_PASSWORD (hardcoded)"

    if ! virt-install \
        --name "$VM_NAME" \
        --memory "$RAM" \
        --vcpus "$VCPUS" \
        --disk "path=$disk_path,format=qcow2" \
        --network network=default \
        --os-variant "$ROCKY_OS_VARIANT" \
        --location "$ISO_PATH" \
        --extra-args "inst.ks=http://$HOST_IP:$HTTP_PORT/ks_$VM_NAME.cfg console=ttyS0,115200n8 inst.text inst.repo=cdrom" \
        --graphics none \
        --console pty,target_type=serial \
        --noautoconsole \
        --wait -1; then

        log_error "Failed to create VM: $VM_NAME"
        exit 1
    fi

    log_success "🎉 VM '$VM_NAME' created successfully!"
    log_cyan "   Access via: virsh console $VM_NAME"
    log_cyan "   SSH (after IP assigned): ssh $USERNAME@<vm-ip>"
    log_cyan "   Disk: $disk_path"
}

# ========================
# MAIN EXECUTION
# ========================
main() {
    log_info "🚀 VirtCrafter Core - Open Source Edition"
    log_info "   One VM. One Command. Zero Input."
    log_info "   GPL v3.0 — https://github.com/ahmadmwaddah/virt-crafter-core"
    echo ""

    ensure_directories
    check_dependencies
    verify_iso
    install_vm
}

# ========================
# CLEANUP ON EXIT
# ========================
cleanup() {
    if [[ -n "$KS_PID" ]] && kill -0 "$KS_PID" 2>/dev/null; then
        kill "$KS_PID" 2>/dev/null || true
    fi
    rm -f "$IMAGE_DIR/http_server.pid"
    rm -f "$IMAGE_DIR/test_http.txt"
}

trap cleanup EXIT

main "$@"