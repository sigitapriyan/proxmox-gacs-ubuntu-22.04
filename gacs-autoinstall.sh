 #!/bin/bash

# Color definitions
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\e[34m'
MAGENTA='\e[35m'
CYAN='\e[36m'
WHITE='\e[97m'
BOLD='\e[1m'
RESET='\e[0m' # Reset all attributes

# Spinner function
spinner() {
    local pid=$1
    local spin='|/-\\'
    while kill -0 $pid 2>/dev/null; do
        for i in $(seq 0 3); do
            printf "\r${CYAN}[%s] ${RESET}" "${spin:$i:1}"
            sleep 0.1
        done
    done
    printf "\r"
}

# Function to show progress percentage
show_progress() {
    local current=$1
    local total=$2
    local percent=$(( current * 100 / total ))
    printf "${YELLOW}[Progress: %d%%]${RESET}\n" "$percent"
}

# Function to run commands with status
run_command() {
    local command="$1"
    local description="$2"
    local current="$3"
    local total="$4"

    printf "${BLUE}%-60s${RESET}" "$description..."
    eval "$command" &>/dev/null &
    pid=$!
    spinner $pid

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Berhasil${RESET}"
    else
        echo -e "${RED}Gagal${RESET}"
        echo -e "${RED}Peringatan: Proses instalasi gagal di langkah: $description.${RESET}"
        echo -e "${YELLOW}Silakan periksa log dan coba lagi.${RESET}"
        exit 1
    fi
    show_progress "$current" "$total"
}

# Banner
print_banner() {
    echo -e "${MAGENTA}${BOLD}"
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║              GENIEACS INSTALLER                   ║"
    echo "║               For Ubuntu 22.04                    ║"
    echo "║              Codex by Kangsigi                    ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# Root and OS checks
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Kesalahan: Skrip ini harus dijalankan sebagai root.${RESET}"
    exit 1
fi

if [ "$(lsb_release -cs)" != "jammy" ]; then
    echo -e "${RED}Kesalahan: Skrip ini hanya mendukung Ubuntu 22.04 (Jammy).${RESET}"
    exit 1
fi

# Set timezone to Asia/Jakarta
echo -e "${BLUE}Mengatur zona waktu ke Asia/Jakarta...${RESET}"
ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime

echo -e "${GREEN}Zona waktu berhasil diatur.${RESET}"

print_banner

# Main installation process
steps=20
current=0

total_steps=$steps
run_command "apt-get update -y" "[$(( ++current ))/$steps] Memperbarui daftar paket" "$current" "$total_steps"

run_command "apt-get install -y nodejs npm" "[$(( ++current ))/$steps] Menginstal Node.js dan npm" "$current" "$total_steps"

run_command "wget -q http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_amd64.deb && dpkg -i libssl1.1_1.1.0g-2ubuntu4_amd64.deb" "[$(( ++current ))/$steps] Menginstal libssl" "$current" "$total_steps"

run_command "curl -fsSL https://www.mongodb.org/static/pgp/server-6.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-org-6.0.gpg" "[$(( ++current ))/$steps] Menambahkan Kunci GPG MongoDB" "$current" "$total_steps"

run_command "echo \"deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-org-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse\" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list" "[$(( ++current ))/$steps] Menambahkan Repository MongoDB" "$current" "$total_steps"

run_command "apt-get update -y" "[$(( ++current ))/$steps] Memperbarui daftar paket kembali" "$current" "$total_steps"

run_command "apt-get install -y mongodb-org" "[$(( ++current ))/$steps] Menginstal MongoDB" "$current" "$total_steps"

run_command "systemctl enable --now mongod" "[$(( ++current ))/$steps] Mengaktifkan dan memulai MongoDB" "$current" "$total_steps"

run_command "npm install -g genieacs@1.2.13" "[$(( ++current ))/$steps] Menginstal GenieACS" "$current" "$total_steps"

run_command "useradd --system --no-create-home --user-group genieacs" "[$(( ++current ))/$steps] Membuat pengguna genieacs" "$current" "$total_steps"

run_command "mkdir -p /opt/genieacs/ext && chown genieacs:genieacs /opt/genieacs/ext" "[$(( ++current ))/$steps] Menyiapkan direktori GenieACS" "$current" "$total_steps"

cat << EOF > /opt/genieacs/genieacs.env
GENIEACS_CWMP_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-cwmp-access.log
GENIEACS_NBI_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-nbi-access.log
GENIEACS_FS_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-fs-access.log
GENIEACS_UI_ACCESS_LOG_FILE=/var/log/genieacs/genieacs-ui-access.log
GENIEACS_DEBUG_FILE=/var/log/genieacs/genieacs-debug.yaml
NODE_OPTIONS=--enable-source-maps
GENIEACS_EXT_DIR=/opt/genieacs/ext
EOF

run_command "node -e \"console.log('GENIEACS_UI_JWT_SECRET=' + require('crypto').randomBytes(128).toString('hex'))\" >> /opt/genieacs/genieacs.env" "[$(( ++current ))/$steps] Membuat JWT secret" "$current" "$total_steps"

run_command "chown genieacs:genieacs /opt/genieacs/genieacs.env && chmod 600 /opt/genieacs/genieacs.env" "[$(( ++current ))/$steps] Mengamankan file lingkungan GenieACS" "$current" "$total_steps"

run_command "mkdir -p /var/log/genieacs && chown genieacs:genieacs /var/log/genieacs" "[$(( ++current ))/$steps] Menyiapkan direktori log" "$current" "$total_steps"

for service in cwmp nbi fs ui; do
    cat << EOF > /etc/systemd/system/genieacs-$service.service
[Unit]
Description=GenieACS $service
After=network.target

[Service]
User=genieacs
EnvironmentFile=/opt/genieacs/genieacs.env
ExecStart=/usr/local/bin/genieacs-$service

[Install]
WantedBy=default.target
EOF
    run_command "systemctl enable --now genieacs-$service" "[$(( ++current ))/$steps] Mengonfigurasi dan memulai layanan $service" "$current" "$total_steps"
done

cat << EOF > /etc/logrotate.d/genieacs
/var/log/genieacs/*.log /var/log/genieacs/*.yaml {
    daily
    rotate 14
    compress
    missingok
    notifempty
}
EOF

run_command "logrotate -f /etc/logrotate.d/genieacs" "[$(( ++current ))/$steps] Menyiapkan rotasi log" "$current" "$total_steps"

echo -e "\n${GREEN}${BOLD}Instalasi berhasil diselesaikan!${RESET}"
