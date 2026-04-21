#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

APP="ctl"
APP_HOME="/opt/${APP}"
APP_ETC="/etc/${APP}"
APP_WWW="/var/www/${APP}"
SING_DIR="/etc/sing-box"
SING_CONFIG="${SING_DIR}/config.json"
CERT_DIR="/etc/ssl/${APP}"
STATE_FILE="${APP_ETC}/state.env"
SELF_BIN="/usr/local/bin/ctl"
SELF_URL_FILE="${APP_ETC}/script-url"
VERSION_FILE="${APP_ETC}/sing-box.version"
CLIENT_INFO="${APP_ETC}/client-info.txt"
META_INFO="${APP_ETC}/subscription.json"
NGINX_CONF="/etc/nginx/conf.d/${APP}.conf"
SYSCTL_CONF="/etc/sysctl.d/98-${APP}.conf"
SING_SERVICE="/etc/systemd/system/sing-box.service"
ACME_HOME="/root/.acme.sh"
ACME_SH="${ACME_HOME}/acme.sh"
SCRIPT_SELF="${BASH_SOURCE[0]:-$0}"
DEFAULT_SCRIPT_URL="https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh"

DEFAULT_ANYTLS_PORT="${CTL_ANYTLS_PORT:-8443}"
DEFAULT_HY2_PORT="${CTL_HY2_PORT:-443}"
DEFAULT_VLESS_PORT="${CTL_VLESS_REALITY_PORT:-8448}"
DEFAULT_SS_PORT="${CTL_SS_PORT:-8388}"
DEFAULT_TUIC_PORT="${CTL_TUIC_PORT:-5443}"
DEFAULT_VMESS_PORT="${CTL_VMESS_PORT:-2083}"
DEFAULT_REALITY_SERVER="${CTL_REALITY_SERVER:-www.apple.com}"
DEFAULT_REALITY_SERVER_PORT="${CTL_REALITY_SERVER_PORT:-443}"
DEFAULT_SS_METHOD="${CTL_SS_METHOD:-chacha20-ietf-poly1305}"
DEFAULT_HY2_OBFS="${CTL_HY2_OBFS_TYPE:-salamander}"

OS_FAMILY=""
CRON_SERVICE=""
OS_NAME=""

DOMAIN="${CTL_DOMAIN:-}"
EMAIL="${CTL_EMAIL:-}"
SELF_UPDATE_URL="${CTL_SCRIPT_URL:-$DEFAULT_SCRIPT_URL}"
ANYTLS_PORT=""
HY2_PORT=""
VLESS_PORT=""
SS_PORT=""
TUIC_PORT=""
VMESS_PORT=""
REALITY_SERVER=""
REALITY_SERVER_PORT=""
SS_METHOD=""
HY2_OBFS_TYPE=""
SUB_TOKEN=""
SUB_PATH=""
ANYTLS_PASSWORD=""
HY2_PASSWORD=""
HY2_OBFS_PASSWORD=""
VLESS_UUID=""
REALITY_PRIVATE_KEY=""
REALITY_PUBLIC_KEY=""
REALITY_SHORT_ID=""
SS_PASSWORD=""
TUIC_UUID=""
TUIC_PASSWORD=""
VMESS_UUID=""
TROJAN_PASSWORD=""
TROJAN_WS_PATH=""
TROJAN_GRPC_SERVICE=""

cecho() {
  local color="$1"
  shift
  printf '\033[%sm%s\033[0m\n' "$color" "$*"
}

info() { cecho "1;32" "[INFO] $*"; }
warn() { cecho "1;33" "[WARN] $*"; }
fail() { cecho "1;31" "[ERROR] $*"; exit 1; }

has() {
  command -v "$1" >/dev/null 2>&1
}

need_root() {
  [ "$(id -u)" -eq 0 ] || fail "Please run this script as root."
}

need_systemd() {
  has systemctl || fail "This script supports only Debian/Ubuntu systems with systemd."
}

ensure_dirs() {
  mkdir -p "$APP_HOME" "$APP_ETC" "$APP_WWW" "$SING_DIR" "$CERT_DIR"
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
  fi
  DOMAIN="${CTL_DOMAIN:-${DOMAIN:-}}"
  EMAIL="${CTL_EMAIL:-${EMAIL:-}}"
  SELF_UPDATE_URL="${CTL_SCRIPT_URL:-${SELF_UPDATE_URL:-}}"
  set_defaults
}

save_state() {
  ensure_dirs
  cat >"$STATE_FILE" <<EOF
DOMAIN="${DOMAIN}"
EMAIL="${EMAIL}"
ANYTLS_PORT="${ANYTLS_PORT}"
HY2_PORT="${HY2_PORT}"
VLESS_PORT="${VLESS_PORT}"
SS_PORT="${SS_PORT}"
TUIC_PORT="${TUIC_PORT}"
VMESS_PORT="${VMESS_PORT}"
REALITY_SERVER="${REALITY_SERVER}"
REALITY_SERVER_PORT="${REALITY_SERVER_PORT}"
SS_METHOD="${SS_METHOD}"
HY2_OBFS_TYPE="${HY2_OBFS_TYPE}"
SUB_TOKEN="${SUB_TOKEN}"
SUB_PATH="${SUB_PATH}"
ANYTLS_PASSWORD="${ANYTLS_PASSWORD}"
HY2_PASSWORD="${HY2_PASSWORD}"
HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD}"
VLESS_UUID="${VLESS_UUID}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY}"
REALITY_SHORT_ID="${REALITY_SHORT_ID}"
SS_PASSWORD="${SS_PASSWORD}"
TUIC_UUID="${TUIC_UUID}"
TUIC_PASSWORD="${TUIC_PASSWORD}"
VMESS_UUID="${VMESS_UUID}"
SELF_UPDATE_URL="${SELF_UPDATE_URL}"
EOF
  if [ -n "${SELF_UPDATE_URL}" ]; then
    printf '%s\n' "${SELF_UPDATE_URL}" >"$SELF_URL_FILE"
  fi
}

ask() {
  local __var="$1"
  local text="$2"
  local default="${3:-}"
  local value=""
  if [ -n "${!__var:-}" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    [ -n "$default" ] || fail "Missing ${__var}. Please pass it via environment variable."
    printf -v "$__var" '%s' "$default"
    return 0
  fi
  if [ -n "$default" ]; then
    read -r -p "${text} [${default}]: " value
    value="${value:-$default}"
  else
    read -r -p "${text}: " value
  fi
  [ -n "$value" ] || fail "${text} cannot be empty."
  printf -v "$__var" '%s' "$value"
}

confirm() {
  local text="$1"
  local answer=""
  if [ ! -t 0 ]; then
    return 1
  fi
  read -r -p "${text} [y/N]: " answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

detect_os() {
  [ -f /etc/os-release ] || fail "Unable to detect the operating system."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
  case "${ID:-}" in
    ubuntu|debian)
      OS_FAMILY="apt"
      CRON_SERVICE="cron"
      ;;
    *)
      case "${ID_LIKE:-}" in
        *debian*)
          OS_FAMILY="apt"
          CRON_SERVICE="cron"
          ;;
        *)
          fail "Only Debian and Ubuntu are supported. Detected: ${OS_NAME}"
          ;;
      esac
      ;;
  esac
}

install_deps() {
  info "Installing dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl wget tar openssl ca-certificates nginx cron unzip grep sed coreutils findutils
  systemctl enable --now "$CRON_SERVICE"
  systemctl enable --now nginx
}

make_temp_file() {
  local tmp_root
  ensure_dirs
  tmp_root="${APP_HOME}/tmp"
  mkdir -p "$tmp_root"
  mktemp "${tmp_root}/tmp.XXXXXX"
}

install_self() {
  local tmp
  tmp="$(make_temp_file)"
  if [ -n "${SELF_UPDATE_URL:-}" ]; then
    curl -fsSL "$SELF_UPDATE_URL" -o "$tmp"
  elif [ -f "$SCRIPT_SELF" ] && [ ! -L "$SCRIPT_SELF" ] && [[ "$SCRIPT_SELF" != /dev/fd/* ]] && [[ "$SCRIPT_SELF" != /proc/self/fd/* ]]; then
    cat "$SCRIPT_SELF" >"$tmp"
  else
    warn "The script is running via a pipe or process substitution, so self-install was skipped. Run 'ctl set-update-url <raw-url>' later if needed."
    rm -f "$tmp"
    return 0
  fi
  install -m 0755 "$tmp" "$SELF_BIN"
  rm -f "$tmp"
  if [ -z "${SELF_UPDATE_URL}" ] && [ -f "$SELF_URL_FILE" ]; then
    SELF_UPDATE_URL="$(head -n1 "$SELF_URL_FILE" 2>/dev/null || true)"
  fi
}

rand_alnum() {
  local n="${1:-24}"
  LC_ALL=C openssl rand -base64 $((n * 2)) | tr -dc 'A-Za-z0-9' | awk -v n="$n" '{ s = s $0 } END { print substr(s, 1, n) }'
}

uuid_new() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
  fi
}

base64_one_line() {
  base64 | tr -d '\n'
}

download_text() {
  curl -fsSL "$1"
}

set_defaults() {
  ANYTLS_PORT="${ANYTLS_PORT:-$DEFAULT_ANYTLS_PORT}"
  HY2_PORT="${HY2_PORT:-$DEFAULT_HY2_PORT}"
  VLESS_PORT="${VLESS_PORT:-$DEFAULT_VLESS_PORT}"
  SS_PORT="${SS_PORT:-$DEFAULT_SS_PORT}"
  TUIC_PORT="${TUIC_PORT:-$DEFAULT_TUIC_PORT}"
  VMESS_PORT="${VMESS_PORT:-$DEFAULT_VMESS_PORT}"
  REALITY_SERVER="${REALITY_SERVER:-$DEFAULT_REALITY_SERVER}"
  REALITY_SERVER_PORT="${REALITY_SERVER_PORT:-$DEFAULT_REALITY_SERVER_PORT}"
  SS_METHOD="${SS_METHOD:-$DEFAULT_SS_METHOD}"
  HY2_OBFS_TYPE="${HY2_OBFS_TYPE:-$DEFAULT_HY2_OBFS}"
}

public_ipv4() {
  curl -fsS4 --max-time 8 https://api.ipify.org 2>/dev/null || true
}

domain_ipv4() {
  getent ahostsv4 "$1" 2>/dev/null | awk 'NR==1 {print $1}'
}

check_dns_hint() {
  local server_ip resolved_ip
  server_ip="$(public_ipv4)"
  resolved_ip="$(domain_ipv4 "$DOMAIN")"
  if [ -n "$server_ip" ] && [ -n "$resolved_ip" ] && [ "$server_ip" != "$resolved_ip" ]; then
    warn "Domain ${DOMAIN} currently resolves to ${resolved_ip}, but the server public IPv4 is ${server_ip}."
    warn "Certificate issuance requires correct DNS. If you changed DNS recently, wait for propagation before continuing."
  fi
}

sysctl_tune() {
  info "Applying optional BBR and UDP/TCP tuning..."
  cat >"$SYSCTL_CONF" <<'EOF'
fs.file-max = 1048576
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
EOF
  sysctl --system >/dev/null 2>&1 || true
}

firewall_open() {
  local tcp_ports udp_ports port
  tcp_ports=("80" "443" "$ANYTLS_PORT" "$VLESS_PORT" "$SS_PORT" "$VMESS_PORT")
  udp_ports=("$HY2_PORT" "$SS_PORT" "$TUIC_PORT")
  if has ufw; then
    for port in "${tcp_ports[@]}"; do ufw allow "${port}/tcp" >/dev/null 2>&1 || true; done
    for port in "${udp_ports[@]}"; do ufw allow "${port}/udp" >/dev/null 2>&1 || true; done
  elif has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    for port in "${tcp_ports[@]}"; do firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true; done
    for port in "${udp_ports[@]}"; do firewall-cmd --permanent --add-port="${port}/udp" >/dev/null 2>&1 || true; done
    firewall-cmd --reload >/dev/null 2>&1 || true
  else
    warn "No supported local firewall manager was detected. Open the required ports in your provider firewall."
  fi
}

arch_name() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s\n' "amd64" ;;
    aarch64|arm64) printf '%s\n' "arm64" ;;
    *) fail "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

sing_api_json() {
  download_text "https://api.github.com/repos/SagerNet/sing-box/releases/latest"
}

sing_latest_version() {
  local api
  api="$(sing_api_json)"
  printf '%s\n' "$api" | sed -nE 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/p' | tail -n1
}

sing_download_url() {
  local arch="$1"
  local api
  api="$(sing_api_json)"
  printf '%s\n' "$api" | grep -Eo "https://[^\"]+linux-${arch}\.tar\.gz" | tail -n1
}

install_sing_box() {
  local arch url version cache_dir tmp_dir tgz bin
  arch="$(arch_name)"
  url="$(sing_download_url "$arch")"
  version="$(sing_latest_version)"
  [ -n "$url" ] || fail "Unable to get the sing-box download URL."
  ensure_dirs
  cache_dir="${APP_HOME}/downloads"
  mkdir -p "$cache_dir"
  tmp_dir="$(mktemp -d "${cache_dir}/sing-box.XXXXXX")"
  tgz="${tmp_dir}/sing-box.tar.gz"
  info "Downloading sing-box ${version} ..."
  if ! curl -fL --retry 3 --connect-timeout 15 "$url" -o "$tgz"; then
    warn "curl download failed, trying wget ..."
    wget -O "$tgz" "$url" || fail "Failed to download sing-box. Check disk space, GitHub connectivity, and write permission for ${cache_dir}."
  fi
  [ -s "$tgz" ] || fail "The downloaded sing-box archive is empty."
  tar -xzf "$tgz" -C "$tmp_dir"
  bin="$(find "$tmp_dir" -type f -name sing-box -print -quit)"
  [ -n "$bin" ] || fail "sing-box binary was not found after extraction."
  install -m 0755 "$bin" /usr/local/bin/sing-box
  printf '%s\n' "$version" >"$VERSION_FILE"
  rm -rf "$tmp_dir"
}

install_acme() {
  if [ ! -x "$ACME_SH" ]; then
    info "Installing acme.sh ..."
    curl -fsSL https://get.acme.sh | sh -s email="$EMAIL"
  fi
  "$ACME_SH" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
  "$ACME_SH" --register-account -m "$EMAIL" --server letsencrypt >/dev/null 2>&1 || true
}

nginx_http_only() {
  mkdir -p "${APP_WWW}/.well-known/acme-challenge" "${APP_WWW}/${SUB_PATH}"
  cat >"$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${APP_WWW};

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ /index.html =404;
    }
}
EOF
  nginx -t
  systemctl reload nginx
}

nginx_https() {
  cat >"$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${APP_WWW};

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};
    root ${APP_WWW};

    ssl_certificate ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    add_header Cache-Control "no-store";

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ /index.html =404;
    }
}
EOF
  nginx -t
  systemctl reload nginx
}

issue_cert() {
  info "Issuing Let's Encrypt ECC certificate..."
  "$ACME_SH" --issue -d "$DOMAIN" --webroot "$APP_WWW" --server letsencrypt --keylength ec-256
  "$ACME_SH" --install-cert -d "$DOMAIN" --ecc \
    --key-file "${CERT_DIR}/privkey.pem" \
    --fullchain-file "${CERT_DIR}/fullchain.pem" \
    --reloadcmd "systemctl reload nginx >/dev/null 2>&1 || true; systemctl restart sing-box >/dev/null 2>&1 || true"
  chmod 600 "${CERT_DIR}/privkey.pem"
  chmod 644 "${CERT_DIR}/fullchain.pem"
}

renew_cert() {
  load_state
  detect_os
  [ -n "${DOMAIN:-}" ] || fail "No installed configuration was found."
  [ -x "$ACME_SH" ] || fail "acme.sh was not found."
  info "Running certificate renewal..."
  "$ACME_SH" --renew -d "$DOMAIN" --ecc --force
  systemctl reload nginx || true
  systemctl restart sing-box || true
  write_client_info
}

reality_keypair() {
  local out
  out="$(/usr/local/bin/sing-box generate reality-keypair)"
  REALITY_PRIVATE_KEY="$(printf '%s\n' "$out" | awk -F': *' '/^[[:space:]]*Private/ { print $2; exit }')"
  REALITY_PUBLIC_KEY="$(printf '%s\n' "$out" | awk -F': *' '/^[[:space:]]*Public/ { print $2; exit }')"
  [ -n "$REALITY_PRIVATE_KEY" ] || fail "Failed to generate the Reality private key."
  [ -n "$REALITY_PUBLIC_KEY" ] || fail "Failed to generate the Reality public key."
}

gen_secrets() {
  if [ "${CTL_RESET_SECRETS:-0}" = "1" ]; then
    ANYTLS_PASSWORD=""
    HY2_PASSWORD=""
    HY2_OBFS_PASSWORD=""
    VLESS_UUID=""
    REALITY_PRIVATE_KEY=""
    REALITY_PUBLIC_KEY=""
    REALITY_SHORT_ID=""
    SS_PASSWORD=""
    TUIC_UUID=""
    TUIC_PASSWORD=""
    VMESS_UUID=""
    SUB_TOKEN=""
    SUB_PATH=""
  fi
  ANYTLS_PASSWORD="${ANYTLS_PASSWORD:-$(rand_alnum 24)}"
  HY2_PASSWORD="${HY2_PASSWORD:-$(rand_alnum 28)}"
  HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD:-$(rand_alnum 20)}"
  VLESS_UUID="${VLESS_UUID:-$(uuid_new)}"
  SS_PASSWORD="${SS_PASSWORD:-$(rand_alnum 24)}"
  TUIC_UUID="${TUIC_UUID:-$(uuid_new)}"
  TUIC_PASSWORD="${TUIC_PASSWORD:-$(rand_alnum 24)}"
  VMESS_UUID="${VMESS_UUID:-$(uuid_new)}"
  REALITY_SHORT_ID="${REALITY_SHORT_ID:-$(openssl rand -hex 8)}"
  SUB_TOKEN="${SUB_TOKEN:-$(openssl rand -hex 16)}"
  SUB_PATH="${SUB_PATH:-sub/${SUB_TOKEN}}"
  if [ -z "${REALITY_PRIVATE_KEY}" ] || [ -z "${REALITY_PUBLIC_KEY}" ]; then
    reality_keypair
  fi
}

write_service() {
  cat >"$SING_SERVICE" <<EOF
[Unit]
Description=sing-box service for ctl
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c ${SING_CONFIG}
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

write_config() {
  cat >"$SING_CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "0.0.0.0",
      "listen_port": ${ANYTLS_PORT},
      "users": [
        {
          "name": "ctl-anytls",
          "password": "${ANYTLS_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "0.0.0.0",
      "listen_port": ${HY2_PORT},
      "users": [
        {
          "name": "ctl-hy2",
          "password": "${HY2_PASSWORD}"
        }
      ],
      "ignore_client_bandwidth": true,
      "obfs": {
        "type": "${HY2_OBFS_TYPE}",
        "password": "${HY2_OBFS_PASSWORD}"
      },
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem"
      }
    },
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "0.0.0.0",
      "listen_port": ${VLESS_PORT},
      "users": [
        {
          "name": "ctl-vless",
          "uuid": "${VLESS_UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${REALITY_SERVER}",
            "server_port": ${REALITY_SERVER_PORT}
          },
          "private_key": "${REALITY_PRIVATE_KEY}",
          "short_id": ["${REALITY_SHORT_ID}"]
        }
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "listen_port": ${SS_PORT},
      "method": "${SS_METHOD}",
      "password": "${SS_PASSWORD}"
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "0.0.0.0",
      "listen_port": ${TUIC_PORT},
      "users": [
        {
          "name": "ctl-tuic",
          "uuid": "${TUIC_UUID}",
          "password": "${TUIC_PASSWORD}"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem"
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "0.0.0.0",
      "listen_port": ${VMESS_PORT},
      "users": [
        {
          "name": "ctl-vmess",
          "uuid": "${VMESS_UUID}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF
}

check_config() {
  /usr/local/bin/sing-box check -c "$SING_CONFIG"
}

start_sing() {
  write_service
  check_config
  systemctl enable --now sing-box
  systemctl restart sing-box
}

ss_uri() {
  local encoded
  encoded="$(printf '%s:%s' "$SS_METHOD" "$SS_PASSWORD" | base64_one_line)"
  printf 'ss://%s@%s:%s#CTL-Shadowsocks\n' "$encoded" "$DOMAIN" "$SS_PORT"
}

vmess_uri() {
  local json
  json=$(cat <<EOF
{"v":"2","ps":"CTL-VMess","add":"${DOMAIN}","port":"${VMESS_PORT}","id":"${VMESS_UUID}","aid":"0","scy":"auto","net":"tcp","type":"none","host":"","path":"","tls":"tls","sni":"${DOMAIN}"}
EOF
)
  printf 'vmess://%s\n' "$(printf '%s' "$json" | base64_one_line)"
}

write_sub_files() {
  local raw_file sub_file html_file raw_content
  mkdir -p "${APP_WWW}/${SUB_PATH}"
  raw_file="${APP_WWW}/${SUB_PATH}/raw.txt"
  sub_file="${APP_WWW}/${SUB_PATH}/sub.txt"
  html_file="${APP_WWW}/${SUB_PATH}/index.html"
  cat >"$raw_file" <<EOF
anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${ANYTLS_PORT}#CTL-AnyTLS
hysteria2://${HY2_PASSWORD}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&insecure=0&obfs=${HY2_OBFS_TYPE}&obfs-password=${HY2_OBFS_PASSWORD}#CTL-Hysteria2
vless://${VLESS_UUID}@${DOMAIN}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#CTL-VLESS-Reality
$(ss_uri)
tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&sni=${DOMAIN}&alpn=h3#CTL-TUIC
$(vmess_uri)
EOF
  raw_content="$(cat "$raw_file")"
  printf '%s' "$raw_content" | base64_one_line >"$sub_file"
  cat >"$html_file" <<EOF
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>CTL Subscription</title>
  <style>
    body { margin: 0; font-family: "Segoe UI","PingFang SC","Microsoft YaHei",sans-serif; background: linear-gradient(135deg,#f5f7fb,#edf6ff); color: #10243f; }
    main { max-width: 760px; margin: 0 auto; padding: 48px 20px 64px; }
    .card { background: rgba(255,255,255,.9); border: 1px solid rgba(16,36,63,.08); border-radius: 20px; padding: 22px; box-shadow: 0 12px 40px rgba(16,36,63,.08); margin-top: 18px; }
    a { color: #0a67d0; text-decoration: none; word-break: break-all; }
    code { display: inline-block; padding: 2px 8px; border-radius: 8px; background: #eff5ff; }
  </style>
</head>
<body>
  <main>
    <h1>CTL Subscription</h1>
    <div class="card">
      <p>Base64 subscription: <a href="/${SUB_PATH}/sub.txt">https://${DOMAIN}/${SUB_PATH}/sub.txt</a></p>
      <p>Raw links: <a href="/${SUB_PATH}/raw.txt">https://${DOMAIN}/${SUB_PATH}/raw.txt</a></p>
      <p>Plain-text info: <a href="/${SUB_PATH}/client-info.txt">https://${DOMAIN}/${SUB_PATH}/client-info.txt</a></p>
    </div>
    <div class="card">
      <p>Panel command: <code>ctl</code></p>
      <p>If you host the script on GitHub Raw, save that URL in the panel so self-updates can stay in sync.</p>
    </div>
  </main>
</body>
</html>
EOF
}

write_client_info() {
  local raw_url sub_url info_url cert_expire sing_ver
  raw_url="https://${DOMAIN}/${SUB_PATH}/raw.txt"
  sub_url="https://${DOMAIN}/${SUB_PATH}/sub.txt"
  info_url="https://${DOMAIN}/${SUB_PATH}/client-info.txt"
  cert_expire="unknown"
  sing_ver="$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 || true)"
  if [ -f "${CERT_DIR}/fullchain.pem" ]; then
    cert_expire="$(openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')"
  fi
  cat >"$CLIENT_INFO" <<EOF
CTL Deployment Information
===========================
System: ${OS_NAME}
Domain: ${DOMAIN}
Panel command: ctl
sing-box: ${sing_ver}
Certificate expiry: ${cert_expire}

Base64 subscription: ${sub_url}
Raw links: ${raw_url}
Plain-text info: ${info_url}

AnyTLS
  host: ${DOMAIN}
  port: ${ANYTLS_PORT}
  password: ${ANYTLS_PASSWORD}
  uri: anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${ANYTLS_PORT}#CTL-AnyTLS

Hysteria2
  host: ${DOMAIN}
  port: ${HY2_PORT}
  auth: ${HY2_PASSWORD}
  sni: ${DOMAIN}
  obfs: ${HY2_OBFS_TYPE}
  obfs-password: ${HY2_OBFS_PASSWORD}
  uri: hysteria2://${HY2_PASSWORD}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&insecure=0&obfs=${HY2_OBFS_TYPE}&obfs-password=${HY2_OBFS_PASSWORD}#CTL-Hysteria2

VLESS + Reality
  host: ${DOMAIN}
  port: ${VLESS_PORT}
  uuid: ${VLESS_UUID}
  flow: xtls-rprx-vision
  reality-server-name: ${REALITY_SERVER}
  reality-public-key: ${REALITY_PUBLIC_KEY}
  reality-short-id: ${REALITY_SHORT_ID}
  uri: vless://${VLESS_UUID}@${DOMAIN}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#CTL-VLESS-Reality

Shadowsocks
  host: ${DOMAIN}
  port: ${SS_PORT}
  method: ${SS_METHOD}
  password: ${SS_PASSWORD}
  uri: $(ss_uri)

TUIC
  host: ${DOMAIN}
  port: ${TUIC_PORT}
  uuid: ${TUIC_UUID}
  password: ${TUIC_PASSWORD}
  sni: ${DOMAIN}
  uri: tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&sni=${DOMAIN}&alpn=h3#CTL-TUIC

VMess
  host: ${DOMAIN}
  port: ${VMESS_PORT}
  uuid: ${VMESS_UUID}
  tls: tls
  uri: $(vmess_uri)
EOF
  cp "$CLIENT_INFO" "${APP_WWW}/${SUB_PATH}/client-info.txt"
  cat >"$META_INFO" <<EOF
{
  "domain": "${DOMAIN}",
  "subscription_base64": "${sub_url}",
  "subscription_raw": "${raw_url}",
  "client_info": "${info_url}"
}
EOF
}

show_info() {
  load_state
  [ -f "$CLIENT_INFO" ] || fail "No node information was generated yet. Please run the installation first."
  cat "$CLIENT_INFO"
}

show_sub() {
  load_state
  [ -n "${DOMAIN:-}" ] || fail "No installed configuration was found."
  printf 'Base64 subscription: https://%s/%s/sub.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Raw links: https://%s/%s/raw.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Plain-text info: https://%s/%s/client-info.txt\n' "$DOMAIN" "$SUB_PATH"
}

set_update_url() {
  local url="${1:-}"
  load_state
  if [ -z "$url" ] && [ -t 0 ]; then
    read -r -p "Enter the script raw URL: " url
  fi
  [ -n "$url" ] || fail "No script update URL was provided."
  SELF_UPDATE_URL="$url"
  printf '%s\n' "$SELF_UPDATE_URL" >"$SELF_URL_FILE"
  save_state
  info "Script update URL saved."
}

update_panel() {
  local url tmp
  load_state
  url="${1:-${SELF_UPDATE_URL:-}}"
  if [ -z "$url" ] && [ -f "$SELF_URL_FILE" ]; then
    url="$(head -n1 "$SELF_URL_FILE" 2>/dev/null || true)"
  fi
  [ -n "$url" ] || fail "No script self-update URL is configured."
  tmp="$(make_temp_file)"
  curl -fsSL "$url" -o "$tmp"
  bash -n "$tmp"
  install -m 0755 "$tmp" "$SELF_BIN"
  rm -f "$tmp"
  SELF_UPDATE_URL="$url"
  save_state
  info "Panel script updated."
}

update_core() {
  local current latest
  load_state
  detect_os
  current="$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 || true)"
  latest="$(sing_latest_version)"
  if printf '%s\n' "$current" | grep -q "$latest"; then
    info "sing-box is already up to date: ${latest}"
    return 0
  fi
  install_sing_box
  check_config
  systemctl restart sing-box
  write_client_info
  info "sing-box updated to ${latest}"
}

update_all() {
  load_state
  [ -f "$STATE_FILE" ] || fail "No installed configuration was found."
  update_core
  if [ -n "${SELF_UPDATE_URL:-}" ] || [ -f "$SELF_URL_FILE" ]; then
    update_panel
  else
    warn "No script self-update URL is configured, so only sing-box was updated."
  fi
  if [ -x "$ACME_SH" ]; then
    "$ACME_SH" --cron --home "$ACME_HOME" >/dev/null 2>&1 || true
  fi
  write_sub_files
  write_client_info
  systemctl reload nginx || true
  systemctl restart sing-box || true
  info "Sync update completed."
}

restart_all() {
  systemctl restart nginx
  systemctl restart sing-box
  info "nginx and sing-box have been restarted."
}

uninstall_all() {
  load_state
  if ! confirm "Confirm uninstall of the CTL multi-protocol stack and panel?"; then
    info "Uninstall cancelled."
    return 0
  fi
  systemctl disable --now sing-box >/dev/null 2>&1 || true
  rm -f "$SING_SERVICE" "$SING_CONFIG" "$NGINX_CONF" "$SELF_BIN" "$SELF_URL_FILE"
  rm -rf "$APP_HOME" "$APP_ETC" "$APP_WWW" "$CERT_DIR"
  systemctl daemon-reload
  if systemctl is-active nginx >/dev/null 2>&1; then
    systemctl reload nginx || true
  fi
  if [ -n "${DOMAIN:-}" ] && [ -x "$ACME_SH" ]; then
    "$ACME_SH" --remove -d "$DOMAIN" --ecc >/dev/null 2>&1 || true
  fi
  info "CTL-managed files were removed. nginx and acme.sh packages were left in place to avoid affecting other sites."
}

install_all() {
  need_root
  need_systemd
  detect_os
  load_state
  set_defaults
  ask DOMAIN "Enter the primary domain that points to this VPS"
  ask EMAIL "Enter the email address for the certificate"
  check_dns_hint
  install_deps
  install_self
  firewall_open
  install_acme
  install_sing_box
  gen_secrets
  save_state
  nginx_http_only
  issue_cert
  write_config
  start_sing
  write_sub_files
  nginx_https
  write_client_info
  save_state
  info "Installation completed. Current node information:"
  show_info
}

menu() {
  cat <<'EOF'

===========================
 CTL Multi-Protocol Panel
===========================
1. Install / Reinstall protocols
2. Show current node information
3. Show subscription links
4. Renew certificate now
5. Sync update (core + panel)
6. Set script self-update URL
7. Restart services
8. Uninstall
9. Enable BBR / network tuning
0. Exit
EOF
}

loop_menu() {
  local choice=""
  while true; do
    menu
    read -r -p "Choose an action: " choice
    case "$choice" in
      1) install_all ;;
      2) show_info ;;
      3) show_sub ;;
      4) renew_cert ;;
      5) update_all ;;
      6) set_update_url ;;
      7) restart_all ;;
      8) uninstall_all ;;
      9) sysctl_tune ;;
      0) exit 0 ;;
      *) warn "Invalid choice. Please try again." ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage:
  bash ctl.sh
  ctl
  ctl install
  ctl show
  ctl sub
  ctl renew
  ctl update
  ctl restart
  ctl uninstall
  ctl tune-network
  ctl set-update-url https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh

Environment variables:
  CTL_DOMAIN=your.domain.com
  CTL_EMAIL=you@example.com
  CTL_SCRIPT_URL=https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh
  CTL_RESET_SECRETS=1

Notes:
  1. 443/tcp is reserved for the HTTPS subscription endpoint.
  2. 443/udp is used by default for Hysteria2.
  3. Default ports: AnyTLS=${DEFAULT_ANYTLS_PORT} VLESS+Reality=${DEFAULT_VLESS_PORT} SS=${DEFAULT_SS_PORT} TUIC=${DEFAULT_TUIC_PORT} VMess=${DEFAULT_VMESS_PORT}
EOF
}

update_all() {
  load_state
  detect_os
  [ -f "$STATE_FILE" ] || fail "No installed configuration was found."
  update_core
  if [ -n "${SELF_UPDATE_URL:-}" ] || [ -f "$SELF_URL_FILE" ]; then
    update_panel
  else
    warn "No script self-update URL is configured, so only the local script copy was kept."
  fi
  gen_secrets
  save_state
  write_config
  check_config
  write_sub_files
  write_client_info
  nginx_https
  if [ -x "$ACME_SH" ]; then
    "$ACME_SH" --cron --home "$ACME_HOME" >/dev/null 2>&1 || true
  fi
  systemctl reload nginx || true
  systemctl restart sing-box || true
  info "Sync update completed. Core, panel, config, subscription files, and nginx routing were refreshed."
}

# Add two broadly-compatible modern options:
# - Trojan + WS + TLS
# - Trojan + gRPC + TLS
# They are not the newest experimental transports, but they are much safer for Clash / Karing / v2rayN / Shadowrocket.
set_defaults() {
  ANYTLS_PORT="${ANYTLS_PORT:-$DEFAULT_ANYTLS_PORT}"
  HY2_PORT="${HY2_PORT:-$DEFAULT_HY2_PORT}"
  VLESS_PORT="${VLESS_PORT:-443}"
  SS_PORT="${SS_PORT:-$DEFAULT_SS_PORT}"
  TUIC_PORT="${TUIC_PORT:-$DEFAULT_TUIC_PORT}"
  VMESS_PORT="${VMESS_PORT:-443}"
  REALITY_SERVER="${REALITY_SERVER:-$DEFAULT_REALITY_SERVER}"
  REALITY_SERVER_PORT="${REALITY_SERVER_PORT:-$DEFAULT_REALITY_SERVER_PORT}"
  SS_METHOD="${SS_METHOD:-$DEFAULT_SS_METHOD}"
  HY2_OBFS_TYPE="${HY2_OBFS_TYPE:-$DEFAULT_HY2_OBFS}"
  VLESS_WS_PATH="${VLESS_WS_PATH:-${CTL_VLESS_WS_PATH:-/ctl-vless}}"
  VMESS_WS_PATH="${VMESS_WS_PATH:-${CTL_VMESS_WS_PATH:-/ctl-vmess}}"
  TROJAN_WS_PATH="${TROJAN_WS_PATH:-${CTL_TROJAN_WS_PATH:-/ctl-trojan-ws}}"
  TROJAN_GRPC_SERVICE="${TROJAN_GRPC_SERVICE:-${CTL_TROJAN_GRPC_SERVICE:-ctl-trojan-grpc}}"
  TROJAN_PASSWORD="${TROJAN_PASSWORD:-}"
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
  fi
  DOMAIN="${CTL_DOMAIN:-${DOMAIN:-}}"
  EMAIL="${CTL_EMAIL:-${EMAIL:-}}"
  SELF_UPDATE_URL="${CTL_SCRIPT_URL:-${SELF_UPDATE_URL:-}}"
  set_defaults
}

save_state() {
  ensure_dirs
  cat >"$STATE_FILE" <<EOF
DOMAIN="${DOMAIN}"
EMAIL="${EMAIL}"
ANYTLS_PORT="${ANYTLS_PORT}"
HY2_PORT="${HY2_PORT}"
VLESS_PORT="${VLESS_PORT}"
SS_PORT="${SS_PORT}"
TUIC_PORT="${TUIC_PORT}"
VMESS_PORT="${VMESS_PORT}"
REALITY_SERVER="${REALITY_SERVER}"
REALITY_SERVER_PORT="${REALITY_SERVER_PORT}"
SS_METHOD="${SS_METHOD}"
HY2_OBFS_TYPE="${HY2_OBFS_TYPE}"
SUB_TOKEN="${SUB_TOKEN}"
SUB_PATH="${SUB_PATH}"
ANYTLS_PASSWORD="${ANYTLS_PASSWORD}"
HY2_PASSWORD="${HY2_PASSWORD}"
HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD}"
VLESS_UUID="${VLESS_UUID}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY}"
REALITY_SHORT_ID="${REALITY_SHORT_ID}"
SS_PASSWORD="${SS_PASSWORD}"
TUIC_UUID="${TUIC_UUID}"
TUIC_PASSWORD="${TUIC_PASSWORD}"
VMESS_UUID="${VMESS_UUID}"
SELF_UPDATE_URL="${SELF_UPDATE_URL}"
VLESS_WS_PATH="${VLESS_WS_PATH}"
VMESS_WS_PATH="${VMESS_WS_PATH}"
TROJAN_PASSWORD="${TROJAN_PASSWORD}"
TROJAN_WS_PATH="${TROJAN_WS_PATH}"
TROJAN_GRPC_SERVICE="${TROJAN_GRPC_SERVICE}"
EOF
  if [ -n "${SELF_UPDATE_URL}" ]; then
    printf '%s\n' "${SELF_UPDATE_URL}" >"$SELF_URL_FILE"
  fi
}

gen_secrets() {
  if [ "${CTL_RESET_SECRETS:-0}" = "1" ]; then
    ANYTLS_PASSWORD=""
    HY2_PASSWORD=""
    HY2_OBFS_PASSWORD=""
    VLESS_UUID=""
    REALITY_PRIVATE_KEY=""
    REALITY_PUBLIC_KEY=""
    REALITY_SHORT_ID=""
    SS_PASSWORD=""
    TUIC_UUID=""
    TUIC_PASSWORD=""
    VMESS_UUID=""
    TROJAN_PASSWORD=""
    SUB_TOKEN=""
    SUB_PATH=""
  fi
  ANYTLS_PASSWORD="${ANYTLS_PASSWORD:-$(rand_alnum 24)}"
  HY2_PASSWORD="${HY2_PASSWORD:-$(rand_alnum 28)}"
  HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD:-$(rand_alnum 20)}"
  VLESS_UUID="${VLESS_UUID:-$(uuid_new)}"
  SS_PASSWORD="${SS_PASSWORD:-$(rand_alnum 24)}"
  TUIC_UUID="${TUIC_UUID:-$(uuid_new)}"
  TUIC_PASSWORD="${TUIC_PASSWORD:-$(rand_alnum 24)}"
  VMESS_UUID="${VMESS_UUID:-$(uuid_new)}"
  TROJAN_PASSWORD="${TROJAN_PASSWORD:-$(rand_alnum 28)}"
  REALITY_SHORT_ID="${REALITY_SHORT_ID:-$(openssl rand -hex 8)}"
  SUB_TOKEN="${SUB_TOKEN:-$(openssl rand -hex 16)}"
  SUB_PATH="${SUB_PATH:-sub/${SUB_TOKEN}}"
  if [ -z "${REALITY_PRIVATE_KEY}" ] || [ -z "${REALITY_PUBLIC_KEY}" ]; then
    reality_keypair
  fi
}

trojan_ws_uri() {
  local trojan_path_encoded
  trojan_path_encoded="${TROJAN_WS_PATH//\//%2F}"
  printf 'trojan://%s@%s:443?security=tls&sni=%s&type=ws&host=%s&path=%s#CTL-Trojan-WS\n' \
    "$TROJAN_PASSWORD" "$DOMAIN" "$DOMAIN" "$DOMAIN" "$trojan_path_encoded"
}

trojan_grpc_uri() {
  printf 'trojan://%s@%s:443?security=tls&sni=%s&type=grpc&serviceName=%s#CTL-Trojan-gRPC\n' \
    "$TROJAN_PASSWORD" "$DOMAIN" "$DOMAIN" "$TROJAN_GRPC_SERVICE"
}

build_common_v2ray_lines() {
  cat <<EOF
hysteria2://${HY2_PASSWORD}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&insecure=0&obfs=${HY2_OBFS_TYPE}&obfs-password=${HY2_OBFS_PASSWORD}#CTL-Hysteria2
$(vless_ws_uri)
$(ss_uri)
tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&sni=${DOMAIN}&alpn=h3#CTL-TUIC
$(vmess_uri)
$(trojan_ws_uri)
$(trojan_grpc_uri)
EOF
}

build_karing_lines() {
  cat <<EOF
anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${ANYTLS_PORT}#CTL-AnyTLS
$(build_common_v2ray_lines)
EOF
}

write_mihomo_yaml() {
  local clash_file="$1"
  cat >"$clash_file" <<EOF
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
ipv6: true
unified-delay: true

proxies:
  - name: "CTL-Hysteria2"
    type: hysteria2
    server: ${DOMAIN}
    port: ${HY2_PORT}
    password: "${HY2_PASSWORD}"
    obfs: ${HY2_OBFS_TYPE}
    obfs-password: "${HY2_OBFS_PASSWORD}"
    sni: ${DOMAIN}
    skip-cert-verify: false
    alpn:
      - h3

  - name: "CTL-TUIC"
    type: tuic
    server: ${DOMAIN}
    port: ${TUIC_PORT}
    uuid: ${TUIC_UUID}
    password: "${TUIC_PASSWORD}"
    udp: true
    sni: ${DOMAIN}
    skip-cert-verify: false
    alpn:
      - h3
    congestion-controller: bbr

  - name: "CTL-Shadowsocks"
    type: ss
    server: ${DOMAIN}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true

  - name: "CTL-VLESS-WS"
    type: vless
    server: ${DOMAIN}
    port: ${VLESS_PORT}
    udp: true
    uuid: ${VLESS_UUID}
    tls: true
    servername: ${DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: ${VLESS_WS_PATH}
      headers:
        Host: ${DOMAIN}

  - name: "CTL-VMess-WS"
    type: vmess
    server: ${DOMAIN}
    port: ${VMESS_PORT}
    udp: true
    uuid: ${VMESS_UUID}
    alterId: 0
    cipher: auto
    tls: true
    servername: ${DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: ${VMESS_WS_PATH}
      headers:
        Host: ${DOMAIN}

  - name: "CTL-Trojan-WS"
    type: trojan
    server: ${DOMAIN}
    port: 443
    password: "${TROJAN_PASSWORD}"
    udp: true
    sni: ${DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: ${TROJAN_WS_PATH}
      headers:
        Host: ${DOMAIN}

  - name: "CTL-Trojan-gRPC"
    type: trojan
    server: ${DOMAIN}
    port: 443
    password: "${TROJAN_PASSWORD}"
    udp: true
    sni: ${DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: false
    network: grpc
    grpc-opts:
      grpc-service-name: ${TROJAN_GRPC_SERVICE}

proxy-groups:
  - name: "CTL-Select"
    type: select
    proxies:
      - "CTL-Hysteria2"
      - "CTL-TUIC"
      - "CTL-VLESS-WS"
      - "CTL-VMess-WS"
      - "CTL-Trojan-WS"
      - "CTL-Trojan-gRPC"
      - "CTL-Shadowsocks"

  - name: "CTL-Auto"
    type: url-test
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    proxies:
      - "CTL-Hysteria2"
      - "CTL-TUIC"
      - "CTL-VLESS-WS"
      - "CTL-VMess-WS"
      - "CTL-Trojan-WS"
      - "CTL-Trojan-gRPC"
      - "CTL-Shadowsocks"

rules:
  - GEOIP,CN,DIRECT
  - MATCH,CTL-Select
EOF
}

nginx_https() {
  cat >"$NGINX_CONF" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${APP_WWW};

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};
    root ${APP_WWW};

    ssl_certificate ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    add_header Cache-Control "no-store";

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location = /${SUB_PATH}/universal {
        if (\$arg_client = clash) { return 302 https://\$host/${SUB_PATH}/clash.yaml; }
        if (\$arg_client = clash-party) { return 302 https://\$host/${SUB_PATH}/clash.yaml; }
        if (\$arg_client = mihomo) { return 302 https://\$host/${SUB_PATH}/clash.yaml; }
        if (\$arg_client = v2rayn) { return 302 https://\$host/${SUB_PATH}/v2rayn.txt; }
        if (\$arg_client = shadowrocket) { return 302 https://\$host/${SUB_PATH}/shadowrocket.txt; }
        if (\$arg_client = karing) { return 302 https://\$host/${SUB_PATH}/karing.txt; }
        if (\$arg_client = raw) { return 302 https://\$host/${SUB_PATH}/raw.txt; }

        if (\$arg_format = clash) { return 302 https://\$host/${SUB_PATH}/clash.yaml; }
        if (\$arg_format = v2ray) { return 302 https://\$host/${SUB_PATH}/sub.txt; }
        if (\$arg_format = raw) { return 302 https://\$host/${SUB_PATH}/raw.txt; }

        if (\$http_user_agent ~* "(clash|mihomo|clash-party|clashparty)") { return 302 https://\$host/${SUB_PATH}/clash.yaml; }
        if (\$http_user_agent ~* "(v2rayn)") { return 302 https://\$host/${SUB_PATH}/v2rayn.txt; }
        if (\$http_user_agent ~* "(shadowrocket)") { return 302 https://\$host/${SUB_PATH}/shadowrocket.txt; }
        if (\$http_user_agent ~* "(karing)") { return 302 https://\$host/${SUB_PATH}/karing.txt; }

        return 302 https://\$host/${SUB_PATH}/index.html;
    }

    location = ${VLESS_WS_PATH} {
        proxy_pass http://127.0.0.1:11080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }

    location = ${VMESS_WS_PATH} {
        proxy_pass http://127.0.0.1:12080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }

    location = ${TROJAN_WS_PATH} {
        proxy_pass http://127.0.0.1:13080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }

    location /${TROJAN_GRPC_SERVICE} {
        grpc_set_header Host \$host;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_read_timeout 86400;
        grpc_pass grpc://127.0.0.1:13081;
    }

    location / {
        try_files \$uri \$uri/ /index.html =404;
    }
}
EOF
  nginx -t
  systemctl reload nginx
}

write_config() {
  cat >"$SING_CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "0.0.0.0",
      "listen_port": ${ANYTLS_PORT},
      "users": [
        {
          "name": "ctl-anytls",
          "password": "${ANYTLS_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "0.0.0.0",
      "listen_port": ${HY2_PORT},
      "users": [
        {
          "name": "ctl-hy2",
          "password": "${HY2_PASSWORD}"
        }
      ],
      "ignore_client_bandwidth": true,
      "obfs": {
        "type": "${HY2_OBFS_TYPE}",
        "password": "${HY2_OBFS_PASSWORD}"
      },
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem"
      }
    },
    {
      "type": "vless",
      "tag": "vless-ws-in",
      "listen": "127.0.0.1",
      "listen_port": 11080,
      "users": [
        {
          "name": "ctl-vless",
          "uuid": "${VLESS_UUID}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${VLESS_WS_PATH}"
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "listen_port": ${SS_PORT},
      "method": "${SS_METHOD}",
      "password": "${SS_PASSWORD}"
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "0.0.0.0",
      "listen_port": ${TUIC_PORT},
      "users": [
        {
          "name": "ctl-tuic",
          "uuid": "${TUIC_UUID}",
          "password": "${TUIC_PASSWORD}"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem"
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-ws-in",
      "listen": "127.0.0.1",
      "listen_port": 12080,
      "users": [
        {
          "name": "ctl-vmess",
          "uuid": "${VMESS_UUID}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${VMESS_WS_PATH}"
      }
    },
    {
      "type": "trojan",
      "tag": "trojan-ws-in",
      "listen": "127.0.0.1",
      "listen_port": 13080,
      "users": [
        {
          "name": "ctl-trojan",
          "password": "${TROJAN_PASSWORD}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${TROJAN_WS_PATH}"
      }
    },
    {
      "type": "trojan",
      "tag": "trojan-grpc-in",
      "listen": "127.0.0.1",
      "listen_port": 13081,
      "users": [
        {
          "name": "ctl-trojan",
          "password": "${TROJAN_PASSWORD}"
        }
      ],
      "transport": {
        "type": "grpc",
        "service_name": "${TROJAN_GRPC_SERVICE}"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF
}

write_client_info() {
  local raw_url sub_url clash_url universal_url v2rayn_url shadowrocket_url karing_url info_url cert_expire sing_ver
  raw_url="https://${DOMAIN}/${SUB_PATH}/raw.txt"
  sub_url="https://${DOMAIN}/${SUB_PATH}/sub.txt"
  clash_url="https://${DOMAIN}/${SUB_PATH}/clash.yaml"
  universal_url="https://${DOMAIN}/${SUB_PATH}/universal"
  v2rayn_url="https://${DOMAIN}/${SUB_PATH}/v2rayn.txt"
  shadowrocket_url="https://${DOMAIN}/${SUB_PATH}/shadowrocket.txt"
  karing_url="https://${DOMAIN}/${SUB_PATH}/karing.txt"
  info_url="https://${DOMAIN}/${SUB_PATH}/client-info.txt"
  cert_expire="unknown"
  sing_ver="$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 || true)"
  if [ -f "${CERT_DIR}/fullchain.pem" ]; then
    cert_expire="$(openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')"
  fi
  cat >"$CLIENT_INFO" <<EOF
CTL Deployment Information
===========================
System: ${OS_NAME}
Domain: ${DOMAIN}
Panel command: ctl
sing-box: ${sing_ver}
Certificate expiry: ${cert_expire}

Universal smart entry: ${universal_url}
Clash / Clash Party: ${clash_url}
v2rayN: ${v2rayn_url}
Shadowrocket: ${shadowrocket_url}
Karing: ${karing_url}
Generic v2ray-style: ${sub_url}
Raw links: ${raw_url}
Plain-text info: ${info_url}

Protocol notes
--------------
AnyTLS is included in Karing and raw outputs only.
Trojan WS and Trojan gRPC were added for broader client compatibility.
Clash-family clients receive a conservative Mihomo YAML profile without AnyTLS.

AnyTLS
  host: ${DOMAIN}
  port: ${ANYTLS_PORT}
  password: ${ANYTLS_PASSWORD}
  note: included in karing.txt and raw.txt
  uri: anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${ANYTLS_PORT}#CTL-AnyTLS

Hysteria2
  host: ${DOMAIN}
  port: ${HY2_PORT}
  auth: ${HY2_PASSWORD}
  sni: ${DOMAIN}
  obfs: ${HY2_OBFS_TYPE}
  obfs-password: ${HY2_OBFS_PASSWORD}
  uri: hysteria2://${HY2_PASSWORD}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&insecure=0&obfs=${HY2_OBFS_TYPE}&obfs-password=${HY2_OBFS_PASSWORD}#CTL-Hysteria2

VLESS + WS + TLS
  host: ${DOMAIN}
  port: ${VLESS_PORT}
  uuid: ${VLESS_UUID}
  path: ${VLESS_WS_PATH}
  uri: $(vless_ws_uri)

Shadowsocks
  host: ${DOMAIN}
  port: ${SS_PORT}
  method: ${SS_METHOD}
  password: ${SS_PASSWORD}
  uri: $(ss_uri)

TUIC
  host: ${DOMAIN}
  port: ${TUIC_PORT}
  uuid: ${TUIC_UUID}
  password: ${TUIC_PASSWORD}
  sni: ${DOMAIN}
  uri: tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&sni=${DOMAIN}&alpn=h3#CTL-TUIC

VMess + WS + TLS
  host: ${DOMAIN}
  port: ${VMESS_PORT}
  uuid: ${VMESS_UUID}
  path: ${VMESS_WS_PATH}
  uri: $(vmess_uri)

Trojan + WS + TLS
  host: ${DOMAIN}
  port: 443
  password: ${TROJAN_PASSWORD}
  path: ${TROJAN_WS_PATH}
  uri: $(trojan_ws_uri)

Trojan + gRPC + TLS
  host: ${DOMAIN}
  port: 443
  password: ${TROJAN_PASSWORD}
  service: ${TROJAN_GRPC_SERVICE}
  uri: $(trojan_grpc_uri)
EOF
  cp "$CLIENT_INFO" "${APP_WWW}/${SUB_PATH}/client-info.txt"
  cat >"$META_INFO" <<EOF
{
  "domain": "${DOMAIN}",
  "subscription_universal": "${universal_url}",
  "subscription_clash": "${clash_url}",
  "subscription_v2rayn": "${v2rayn_url}",
  "subscription_shadowrocket": "${shadowrocket_url}",
  "subscription_karing": "${karing_url}",
  "subscription_base64": "${sub_url}",
  "subscription_raw": "${raw_url}",
  "client_info": "${info_url}"
}
EOF
}

usage() {
  cat <<EOF
Usage:
  bash ctl.sh
  ctl
  ctl install
  ctl show
  ctl sub
  ctl renew
  ctl update
  ctl restart
  ctl uninstall
  ctl tune-network
  ctl set-update-url https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh

Environment variables:
  CTL_DOMAIN=your.domain.com
  CTL_EMAIL=you@example.com
  CTL_SCRIPT_URL=https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh
  CTL_VLESS_WS_PATH=/ctl-vless
  CTL_VMESS_WS_PATH=/ctl-vmess
  CTL_TROJAN_WS_PATH=/ctl-trojan-ws
  CTL_TROJAN_GRPC_SERVICE=ctl-trojan-grpc
  CTL_RESET_SECRETS=1

Notes:
  1. 443/tcp serves the subscription site plus VLESS/VMess/Trojan WS+TLS and Trojan gRPC+TLS.
  2. 443/udp is used by default for Hysteria2.
  3. Client-specific subscriptions are generated to reduce import errors.
  4. Use /clash.yaml for Clash-family clients, /v2rayn.txt for v2rayN, /shadowrocket.txt for Shadowrocket, /karing.txt for Karing, and /universal for smart redirects.
  5. AnyTLS is excluded from Clash and generic v2ray-style feeds, and kept only in Karing and raw outputs.
  6. Trojan WS and Trojan gRPC were added as extra broadly-compatible options.
EOF
}

# Clean English overrides. These replace earlier mojibake-prone definitions.
need_root() {
  [ "$(id -u)" -eq 0 ] || fail "Please run this script as root."
}

need_systemd() {
  has systemctl || fail "This script supports only Debian/Ubuntu systems with systemd."
}

ask() {
  local __var="$1"
  local text="$2"
  local default="${3:-}"
  local value=""
  if [ -n "${!__var:-}" ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    [ -n "$default" ] || fail "Missing ${__var}. Please pass it via environment variable."
    printf -v "$__var" '%s' "$default"
    return 0
  fi
  if [ -n "$default" ]; then
    read -r -p "${text} [${default}]: " value
    value="${value:-$default}"
  else
    read -r -p "${text}: " value
  fi
  [ -n "$value" ] || fail "${text} cannot be empty."
  printf -v "$__var" '%s' "$value"
}

detect_os() {
  [ -f /etc/os-release ] || fail "Unable to detect the operating system."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_NAME="${PRETTY_NAME:-${NAME:-Linux}}"
  case "${ID:-}" in
    ubuntu|debian)
      OS_FAMILY="apt"
      CRON_SERVICE="cron"
      ;;
    *)
      case "${ID_LIKE:-}" in
        *debian*)
          OS_FAMILY="apt"
          CRON_SERVICE="cron"
          ;;
        *)
          fail "Only Debian and Ubuntu are supported. Detected: ${OS_NAME}"
          ;;
      esac
      ;;
  esac
}

install_deps() {
  info "Installing dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl wget tar openssl ca-certificates nginx cron unzip grep sed coreutils findutils
  systemctl enable --now "$CRON_SERVICE"
  systemctl enable --now nginx
}

install_self() {
  local tmp
  tmp="$(make_temp_file)"
  if [ -n "${SELF_UPDATE_URL:-}" ]; then
    curl -fsSL "$SELF_UPDATE_URL" -o "$tmp"
  elif [ -f "$SCRIPT_SELF" ] && [ ! -L "$SCRIPT_SELF" ] && [[ "$SCRIPT_SELF" != /dev/fd/* ]] && [[ "$SCRIPT_SELF" != /proc/self/fd/* ]]; then
    cat "$SCRIPT_SELF" >"$tmp"
  else
    warn "The script is running via a pipe or process substitution, so self-install was skipped. Run 'ctl set-update-url <raw-url>' later if needed."
    rm -f "$tmp"
    return 0
  fi
  install -m 0755 "$tmp" "$SELF_BIN"
  rm -f "$tmp"
  if [ -z "${SELF_UPDATE_URL}" ] && [ -f "$SELF_URL_FILE" ]; then
    SELF_UPDATE_URL="$(head -n1 "$SELF_URL_FILE" 2>/dev/null || true)"
  fi
}

check_dns_hint() {
  local server_ip resolved_ip
  server_ip="$(public_ipv4)"
  resolved_ip="$(domain_ipv4 "$DOMAIN")"
  if [ -n "$server_ip" ] && [ -n "$resolved_ip" ] && [ "$server_ip" != "$resolved_ip" ]; then
    warn "Domain ${DOMAIN} currently resolves to ${resolved_ip}, but the server public IPv4 is ${server_ip}."
    warn "Certificate issuance requires correct DNS. If you changed DNS recently, wait for propagation before continuing."
  fi
}

sysctl_tune() {
  info "Applying optional BBR and UDP/TCP tuning..."
  cat >"$SYSCTL_CONF" <<'EOF'
fs.file-max = 1048576
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
EOF
  sysctl --system >/dev/null 2>&1 || true
}

firewall_open() {
  local tcp_ports udp_ports port
  tcp_ports=("80" "443" "$ANYTLS_PORT" "$VLESS_PORT" "$SS_PORT" "$VMESS_PORT")
  udp_ports=("$HY2_PORT" "$SS_PORT" "$TUIC_PORT")
  if has ufw; then
    for port in "${tcp_ports[@]}"; do ufw allow "${port}/tcp" >/dev/null 2>&1 || true; done
    for port in "${udp_ports[@]}"; do ufw allow "${port}/udp" >/dev/null 2>&1 || true; done
  elif has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    for port in "${tcp_ports[@]}"; do firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true; done
    for port in "${udp_ports[@]}"; do firewall-cmd --permanent --add-port="${port}/udp" >/dev/null 2>&1 || true; done
    firewall-cmd --reload >/dev/null 2>&1 || true
  else
    warn "No supported local firewall manager was detected. If your provider uses a cloud firewall, open the required ports there."
  fi
}

arch_name() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s\n' "amd64" ;;
    aarch64|arm64) printf '%s\n' "arm64" ;;
    *) fail "Unsupported CPU architecture: $(uname -m)" ;;
  esac
}

install_sing_box() {
  local arch url version cache_dir tmp_dir tgz bin
  arch="$(arch_name)"
  url="$(sing_download_url "$arch")"
  version="$(sing_latest_version)"
  [ -n "$url" ] || fail "Unable to get the sing-box download URL."
  ensure_dirs
  cache_dir="${APP_HOME}/downloads"
  mkdir -p "$cache_dir"
  tmp_dir="$(mktemp -d "${cache_dir}/sing-box.XXXXXX")"
  tgz="${tmp_dir}/sing-box.tar.gz"
  info "Downloading sing-box ${version} ..."
  if ! curl -fL --retry 3 --connect-timeout 15 "$url" -o "$tgz"; then
    warn "curl download failed, trying wget ..."
    wget -O "$tgz" "$url" || fail "Failed to download sing-box. Check disk space, GitHub connectivity, and write permission for ${cache_dir}."
  fi
  [ -s "$tgz" ] || fail "The downloaded sing-box archive is empty."
  tar -xzf "$tgz" -C "$tmp_dir"
  bin="$(find "$tmp_dir" -type f -name sing-box -print -quit)"
  [ -n "$bin" ] || fail "sing-box binary was not found after extraction."
  install -m 0755 "$bin" /usr/local/bin/sing-box
  printf '%s\n' "$version" >"$VERSION_FILE"
  rm -rf "$tmp_dir"
}

install_acme() {
  if [ ! -x "$ACME_SH" ]; then
    info "Installing acme.sh ..."
    curl -fsSL https://get.acme.sh | sh -s email="$EMAIL"
  fi
  "$ACME_SH" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
  "$ACME_SH" --register-account -m "$EMAIL" --server letsencrypt >/dev/null 2>&1 || true
}

issue_cert() {
  info "Issuing Let's Encrypt ECC certificate..."
  "$ACME_SH" --issue -d "$DOMAIN" --webroot "$APP_WWW" --server letsencrypt --keylength ec-256
  "$ACME_SH" --install-cert -d "$DOMAIN" --ecc \
    --key-file "${CERT_DIR}/privkey.pem" \
    --fullchain-file "${CERT_DIR}/fullchain.pem" \
    --reloadcmd "systemctl reload nginx >/dev/null 2>&1 || true; systemctl restart sing-box >/dev/null 2>&1 || true"
  chmod 600 "${CERT_DIR}/privkey.pem"
  chmod 644 "${CERT_DIR}/fullchain.pem"
}

renew_cert() {
  load_state
  detect_os
  [ -n "${DOMAIN:-}" ] || fail "No installed configuration was found."
  [ -x "$ACME_SH" ] || fail "acme.sh was not found."
  info "Running certificate renewal..."
  "$ACME_SH" --renew -d "$DOMAIN" --ecc --force
  systemctl reload nginx || true
  systemctl restart sing-box || true
  write_client_info
}

reality_keypair() {
  local out
  out="$(/usr/local/bin/sing-box generate reality-keypair)"
  REALITY_PRIVATE_KEY="$(printf '%s\n' "$out" | awk -F': *' '/^[[:space:]]*Private/ { print $2; exit }')"
  REALITY_PUBLIC_KEY="$(printf '%s\n' "$out" | awk -F': *' '/^[[:space:]]*Public/ { print $2; exit }')"
  [ -n "$REALITY_PRIVATE_KEY" ] || fail "Failed to generate the Reality private key."
  [ -n "$REALITY_PUBLIC_KEY" ] || fail "Failed to generate the Reality public key."
}

write_sub_files() {
  local raw_file sub_file html_file raw_content
  mkdir -p "${APP_WWW}/${SUB_PATH}"
  raw_file="${APP_WWW}/${SUB_PATH}/raw.txt"
  sub_file="${APP_WWW}/${SUB_PATH}/sub.txt"
  html_file="${APP_WWW}/${SUB_PATH}/index.html"
  cat >"$raw_file" <<EOF
anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${ANYTLS_PORT}#CTL-AnyTLS
hysteria2://${HY2_PASSWORD}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&insecure=0&obfs=${HY2_OBFS_TYPE}&obfs-password=${HY2_OBFS_PASSWORD}#CTL-Hysteria2
vless://${VLESS_UUID}@${DOMAIN}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#CTL-VLESS-Reality
$(ss_uri)
tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&sni=${DOMAIN}&alpn=h3#CTL-TUIC
$(vmess_uri)
EOF
  raw_content="$(cat "$raw_file")"
  printf '%s' "$raw_content" | base64_one_line >"$sub_file"
  cat >"$html_file" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>CTL Subscription</title>
  <style>
    body { margin: 0; font-family: "Segoe UI","Helvetica Neue",Arial,sans-serif; background: linear-gradient(135deg,#f5f7fb,#edf6ff); color: #10243f; }
    main { max-width: 760px; margin: 0 auto; padding: 48px 20px 64px; }
    .card { background: rgba(255,255,255,.9); border: 1px solid rgba(16,36,63,.08); border-radius: 20px; padding: 22px; box-shadow: 0 12px 40px rgba(16,36,63,.08); margin-top: 18px; }
    a { color: #0a67d0; text-decoration: none; word-break: break-all; }
    code { display: inline-block; padding: 2px 8px; border-radius: 8px; background: #eff5ff; }
  </style>
</head>
<body>
  <main>
    <h1>CTL Subscription</h1>
    <div class="card">
      <p>Base64 subscription: <a href="/${SUB_PATH}/sub.txt">https://${DOMAIN}/${SUB_PATH}/sub.txt</a></p>
      <p>Raw links: <a href="/${SUB_PATH}/raw.txt">https://${DOMAIN}/${SUB_PATH}/raw.txt</a></p>
      <p>Plain-text node info: <a href="/${SUB_PATH}/client-info.txt">https://${DOMAIN}/${SUB_PATH}/client-info.txt</a></p>
    </div>
    <div class="card">
      <p>Panel command: <code>ctl</code></p>
      <p>If this script is published on GitHub Raw, save that URL in the panel to enable self-updates.</p>
    </div>
  </main>
</body>
</html>
EOF
}

write_client_info() {
  local raw_url sub_url info_url cert_expire sing_ver
  raw_url="https://${DOMAIN}/${SUB_PATH}/raw.txt"
  sub_url="https://${DOMAIN}/${SUB_PATH}/sub.txt"
  info_url="https://${DOMAIN}/${SUB_PATH}/client-info.txt"
  cert_expire="unknown"
  sing_ver="$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 || true)"
  if [ -f "${CERT_DIR}/fullchain.pem" ]; then
    cert_expire="$(openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')"
  fi
  cat >"$CLIENT_INFO" <<EOF
CTL Deployment Information
===========================
System: ${OS_NAME}
Domain: ${DOMAIN}
Panel command: ctl
sing-box: ${sing_ver}
Certificate expiry: ${cert_expire}

Base64 subscription: ${sub_url}
Raw links: ${raw_url}
Plain-text info: ${info_url}

AnyTLS
  host: ${DOMAIN}
  port: ${ANYTLS_PORT}
  password: ${ANYTLS_PASSWORD}
  uri: anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${ANYTLS_PORT}#CTL-AnyTLS

Hysteria2
  host: ${DOMAIN}
  port: ${HY2_PORT}
  auth: ${HY2_PASSWORD}
  sni: ${DOMAIN}
  obfs: ${HY2_OBFS_TYPE}
  obfs-password: ${HY2_OBFS_PASSWORD}
  uri: hysteria2://${HY2_PASSWORD}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&insecure=0&obfs=${HY2_OBFS_TYPE}&obfs-password=${HY2_OBFS_PASSWORD}#CTL-Hysteria2

VLESS + Reality
  host: ${DOMAIN}
  port: ${VLESS_PORT}
  uuid: ${VLESS_UUID}
  flow: xtls-rprx-vision
  reality-server-name: ${REALITY_SERVER}
  reality-public-key: ${REALITY_PUBLIC_KEY}
  reality-short-id: ${REALITY_SHORT_ID}
  uri: vless://${VLESS_UUID}@${DOMAIN}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#CTL-VLESS-Reality

Shadowsocks
  host: ${DOMAIN}
  port: ${SS_PORT}
  method: ${SS_METHOD}
  password: ${SS_PASSWORD}
  uri: $(ss_uri)

TUIC
  host: ${DOMAIN}
  port: ${TUIC_PORT}
  uuid: ${TUIC_UUID}
  password: ${TUIC_PASSWORD}
  sni: ${DOMAIN}
  uri: tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&sni=${DOMAIN}&alpn=h3#CTL-TUIC

VMess
  host: ${DOMAIN}
  port: ${VMESS_PORT}
  uuid: ${VMESS_UUID}
  tls: tls
  uri: $(vmess_uri)
EOF
  cp "$CLIENT_INFO" "${APP_WWW}/${SUB_PATH}/client-info.txt"
  cat >"$META_INFO" <<EOF
{
  "domain": "${DOMAIN}",
  "subscription_base64": "${sub_url}",
  "subscription_raw": "${raw_url}",
  "client_info": "${info_url}"
}
EOF
}

show_info() {
  load_state
  [ -f "$CLIENT_INFO" ] || fail "No node information was generated yet. Please run the installation first."
  cat "$CLIENT_INFO"
}

show_sub() {
  load_state
  [ -n "${DOMAIN:-}" ] || fail "No installed configuration was found."
  printf 'Base64 subscription: https://%s/%s/sub.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Raw links: https://%s/%s/raw.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Plain-text info: https://%s/%s/client-info.txt\n' "$DOMAIN" "$SUB_PATH"
}

set_update_url() {
  local url="${1:-}"
  load_state
  if [ -z "$url" ] && [ -t 0 ]; then
    read -r -p "Enter the script raw URL: " url
  fi
  [ -n "$url" ] || fail "No script update URL was provided."
  SELF_UPDATE_URL="$url"
  printf '%s\n' "$SELF_UPDATE_URL" >"$SELF_URL_FILE"
  save_state
  info "Script update URL saved."
}

update_panel() {
  local url tmp
  load_state
  url="${1:-${SELF_UPDATE_URL:-}}"
  if [ -z "$url" ] && [ -f "$SELF_URL_FILE" ]; then
    url="$(head -n1 "$SELF_URL_FILE" 2>/dev/null || true)"
  fi
  [ -n "$url" ] || fail "No script self-update URL is configured."
  tmp="$(make_temp_file)"
  curl -fsSL "$url" -o "$tmp"
  bash -n "$tmp"
  install -m 0755 "$tmp" "$SELF_BIN"
  rm -f "$tmp"
  SELF_UPDATE_URL="$url"
  save_state
  info "Panel script updated."
}

update_core() {
  local current latest
  load_state
  detect_os
  current="$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 || true)"
  latest="$(sing_latest_version)"
  if printf '%s\n' "$current" | grep -q "$latest"; then
    info "sing-box is already up to date: ${latest}"
    return 0
  fi
  install_sing_box
  check_config
  systemctl restart sing-box
  write_client_info
  info "sing-box updated to ${latest}"
}

update_all() {
  load_state
  [ -f "$STATE_FILE" ] || fail "No installed configuration was found."
  update_core
  if [ -n "${SELF_UPDATE_URL:-}" ] || [ -f "$SELF_URL_FILE" ]; then
    update_panel
  else
    warn "No script self-update URL is configured, so only sing-box was updated."
  fi
  if [ -x "$ACME_SH" ]; then
    "$ACME_SH" --cron --home "$ACME_HOME" >/dev/null 2>&1 || true
  fi
  write_sub_files
  write_client_info
  systemctl reload nginx || true
  systemctl restart sing-box || true
  info "Sync update completed."
}

restart_all() {
  systemctl restart nginx
  systemctl restart sing-box
  info "nginx and sing-box have been restarted."
}

uninstall_all() {
  load_state
  if ! confirm "Uninstall CTL multi-protocol stack and panel?"; then
    info "Uninstall cancelled."
    return 0
  fi
  systemctl disable --now sing-box >/dev/null 2>&1 || true
  rm -f "$SING_SERVICE" "$SING_CONFIG" "$NGINX_CONF" "$SELF_BIN" "$SELF_URL_FILE"
  rm -rf "$APP_HOME" "$APP_ETC" "$APP_WWW" "$CERT_DIR"
  systemctl daemon-reload
  if systemctl is-active nginx >/dev/null 2>&1; then
    systemctl reload nginx || true
  fi
  if [ -n "${DOMAIN:-}" ] && [ -x "$ACME_SH" ]; then
    "$ACME_SH" --remove -d "$DOMAIN" --ecc >/dev/null 2>&1 || true
  fi
  info "CTL-managed files were removed. nginx and acme.sh packages were left in place to avoid affecting other sites."
}

install_all() {
  need_root
  need_systemd
  detect_os
  load_state
  set_defaults
  ask DOMAIN "Enter the primary domain pointing to this VPS"
  ask EMAIL "Enter the certificate email"
  check_dns_hint
  install_deps
  install_self
  firewall_open
  install_acme
  install_sing_box
  gen_secrets
  save_state
  nginx_http_only
  issue_cert
  write_config
  start_sing
  write_sub_files
  nginx_https
  write_client_info
  save_state
  info "Installation completed. Current node information:"
  show_info
}

menu() {
  cat <<'EOF'

===========================
 CTL Multi-Protocol Panel
===========================
1. Install / Reinstall protocols
2. Show current node information
3. Show subscription links
4. Renew certificate now
5. Sync update (core + panel)
6. Set script self-update URL
7. Restart services
8. Uninstall
9. Enable BBR / network tuning
10. Check AI / streaming / social reachability
0. Exit
EOF
}

loop_menu() {
  local choice=""
  while true; do
    menu
    read -r -p "Choose an action: " choice
    case "$choice" in
      1) install_all ;;
      2) show_info ;;
      3) show_sub ;;
      4) renew_cert ;;
      5) update_all ;;
      6) set_update_url ;;
      7) restart_all ;;
      8) uninstall_all ;;
      9) sysctl_tune ;;
      10) site_check ;;
      0) exit 0 ;;
      *) warn "Invalid choice. Please try again." ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage:
  bash ctl.sh
  ctl
  ctl install
  ctl show
  ctl sub
  ctl renew
  ctl update
  ctl restart
  ctl uninstall
  ctl tune-network
  ctl set-update-url https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh

Environment variables:
  CTL_DOMAIN=your.domain.com
  CTL_EMAIL=you@example.com
  CTL_SCRIPT_URL=https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh
  CTL_RESET_SECRETS=1

Notes:
  1. 443/tcp is reserved for the HTTPS subscription endpoint.
  2. 443/udp is used by default for Hysteria2.
  3. Default ports: AnyTLS=${DEFAULT_ANYTLS_PORT} VLESS+Reality=${DEFAULT_VLESS_PORT} SS=${DEFAULT_SS_PORT} TUIC=${DEFAULT_TUIC_PORT} VMess=${DEFAULT_VMESS_PORT}
EOF
}

# Client compatibility overrides for v2rayN / Clash Party:
# - VLESS becomes WebSocket + TLS on 443 via nginx
# - VMess becomes WebSocket + TLS on 443 via nginx
# - A Clash/Mihomo YAML subscription is generated in addition to the v2ray-style base64 subscription
set_defaults() {
  ANYTLS_PORT="${ANYTLS_PORT:-$DEFAULT_ANYTLS_PORT}"
  HY2_PORT="${HY2_PORT:-$DEFAULT_HY2_PORT}"
  VLESS_PORT="${VLESS_PORT:-443}"
  SS_PORT="${SS_PORT:-$DEFAULT_SS_PORT}"
  TUIC_PORT="${TUIC_PORT:-$DEFAULT_TUIC_PORT}"
  VMESS_PORT="${VMESS_PORT:-443}"
  REALITY_SERVER="${REALITY_SERVER:-$DEFAULT_REALITY_SERVER}"
  REALITY_SERVER_PORT="${REALITY_SERVER_PORT:-$DEFAULT_REALITY_SERVER_PORT}"
  SS_METHOD="${SS_METHOD:-$DEFAULT_SS_METHOD}"
  HY2_OBFS_TYPE="${HY2_OBFS_TYPE:-$DEFAULT_HY2_OBFS}"
  VLESS_WS_PATH="${VLESS_WS_PATH:-${CTL_VLESS_WS_PATH:-/ctl-vless}}"
  VMESS_WS_PATH="${VMESS_WS_PATH:-${CTL_VMESS_WS_PATH:-/ctl-vmess}}"
}

save_state() {
  ensure_dirs
  cat >"$STATE_FILE" <<EOF
DOMAIN="${DOMAIN}"
EMAIL="${EMAIL}"
ANYTLS_PORT="${ANYTLS_PORT}"
HY2_PORT="${HY2_PORT}"
VLESS_PORT="${VLESS_PORT}"
SS_PORT="${SS_PORT}"
TUIC_PORT="${TUIC_PORT}"
VMESS_PORT="${VMESS_PORT}"
REALITY_SERVER="${REALITY_SERVER}"
REALITY_SERVER_PORT="${REALITY_SERVER_PORT}"
SS_METHOD="${SS_METHOD}"
HY2_OBFS_TYPE="${HY2_OBFS_TYPE}"
SUB_TOKEN="${SUB_TOKEN}"
SUB_PATH="${SUB_PATH}"
ANYTLS_PASSWORD="${ANYTLS_PASSWORD}"
HY2_PASSWORD="${HY2_PASSWORD}"
HY2_OBFS_PASSWORD="${HY2_OBFS_PASSWORD}"
VLESS_UUID="${VLESS_UUID}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY}"
REALITY_SHORT_ID="${REALITY_SHORT_ID}"
SS_PASSWORD="${SS_PASSWORD}"
TUIC_UUID="${TUIC_UUID}"
TUIC_PASSWORD="${TUIC_PASSWORD}"
VMESS_UUID="${VMESS_UUID}"
SELF_UPDATE_URL="${SELF_UPDATE_URL}"
VLESS_WS_PATH="${VLESS_WS_PATH}"
VMESS_WS_PATH="${VMESS_WS_PATH}"
EOF
  if [ -n "${SELF_UPDATE_URL}" ]; then
    printf '%s\n' "${SELF_UPDATE_URL}" >"$SELF_URL_FILE"
  fi
}

load_state() {
  if [ -f "$STATE_FILE" ]; then
    # shellcheck disable=SC1090
    . "$STATE_FILE"
  fi
  DOMAIN="${CTL_DOMAIN:-${DOMAIN:-}}"
  EMAIL="${CTL_EMAIL:-${EMAIL:-}}"
  SELF_UPDATE_URL="${CTL_SCRIPT_URL:-${SELF_UPDATE_URL:-}}"
}

firewall_open() {
  local tcp_ports udp_ports port
  tcp_ports=("80" "443" "$ANYTLS_PORT" "$SS_PORT")
  udp_ports=("$HY2_PORT" "$SS_PORT" "$TUIC_PORT")
  if has ufw; then
    for port in "${tcp_ports[@]}"; do ufw allow "${port}/tcp" >/dev/null 2>&1 || true; done
    for port in "${udp_ports[@]}"; do ufw allow "${port}/udp" >/dev/null 2>&1 || true; done
  elif has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
    for port in "${tcp_ports[@]}"; do firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true; done
    for port in "${udp_ports[@]}"; do firewall-cmd --permanent --add-port="${port}/udp" >/dev/null 2>&1 || true; done
    firewall-cmd --reload >/dev/null 2>&1 || true
  else
    warn "No supported local firewall manager was detected. Open the required ports in your provider firewall: 80/tcp, 443/tcp, 443/udp, ${ANYTLS_PORT}/tcp, ${SS_PORT}/tcp+udp, ${TUIC_PORT}/udp."
  fi
}

nginx_http_only() {
  mkdir -p "${APP_WWW}/.well-known/acme-challenge" "${APP_WWW}/${SUB_PATH}"
  cat >"$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${APP_WWW};

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ /index.html =404;
    }
}
EOF
  nginx -t
  systemctl reload nginx
}

nginx_https() {
  cat >"$NGINX_CONF" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${APP_WWW};

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};
    root ${APP_WWW};

    ssl_certificate ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    add_header Cache-Control "no-store";

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location = /${SUB_PATH}/universal {
        if (\$arg_format = clash) {
            return 302 https://\$host/${SUB_PATH}/clash.yaml;
        }
        if (\$arg_format = v2ray) {
            return 302 https://\$host/${SUB_PATH}/sub.txt;
        }
        if (\$arg_format = raw) {
            return 302 https://\$host/${SUB_PATH}/raw.txt;
        }
        if (\$http_user_agent ~* "(clash|mihomo|clash-party|clashparty)") {
            return 302 https://\$host/${SUB_PATH}/clash.yaml;
        }
        if (\$http_user_agent ~* "(v2rayn|shadowrocket|karing|sing-box)") {
            return 302 https://\$host/${SUB_PATH}/sub.txt;
        }
        return 302 https://\$host/${SUB_PATH}/index.html;
    }

    location = ${VLESS_WS_PATH} {
        proxy_pass http://127.0.0.1:11080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }

    location = ${VMESS_WS_PATH} {
        proxy_pass http://127.0.0.1:12080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }

    location / {
        try_files \$uri \$uri/ /index.html =404;
    }
}
EOF
  nginx -t
  systemctl reload nginx
}

write_config() {
  cat >"$SING_CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "0.0.0.0",
      "listen_port": ${ANYTLS_PORT},
      "users": [
        {
          "name": "ctl-anytls",
          "password": "${ANYTLS_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "0.0.0.0",
      "listen_port": ${HY2_PORT},
      "users": [
        {
          "name": "ctl-hy2",
          "password": "${HY2_PASSWORD}"
        }
      ],
      "ignore_client_bandwidth": true,
      "obfs": {
        "type": "${HY2_OBFS_TYPE}",
        "password": "${HY2_OBFS_PASSWORD}"
      },
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem"
      }
    },
    {
      "type": "vless",
      "tag": "vless-ws-in",
      "listen": "127.0.0.1",
      "listen_port": 11080,
      "users": [
        {
          "name": "ctl-vless",
          "uuid": "${VLESS_UUID}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${VLESS_WS_PATH}"
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "0.0.0.0",
      "listen_port": ${SS_PORT},
      "method": "${SS_METHOD}",
      "password": "${SS_PASSWORD}"
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "0.0.0.0",
      "listen_port": ${TUIC_PORT},
      "users": [
        {
          "name": "ctl-tuic",
          "uuid": "${TUIC_UUID}",
          "password": "${TUIC_PASSWORD}"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem"
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-ws-in",
      "listen": "127.0.0.1",
      "listen_port": 12080,
      "users": [
        {
          "name": "ctl-vmess",
          "uuid": "${VMESS_UUID}",
          "alterId": 0
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${VMESS_WS_PATH}"
      }
    },
    {
      "type": "trojan",
      "tag": "trojan-ws-in",
      "listen": "127.0.0.1",
      "listen_port": 13080,
      "users": [
        {
          "name": "ctl-trojan",
          "password": "${TROJAN_PASSWORD}"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "${TROJAN_WS_PATH}"
      }
    },
    {
      "type": "trojan",
      "tag": "trojan-grpc-in",
      "listen": "127.0.0.1",
      "listen_port": 13081,
      "users": [
        {
          "name": "ctl-trojan",
          "password": "${TROJAN_PASSWORD}"
        }
      ],
      "transport": {
        "type": "grpc",
        "service_name": "${TROJAN_GRPC_SERVICE}"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF
}

vmess_uri() {
  local json
  json=$(cat <<EOF
{"v":"2","ps":"CTL-VMess-WS","add":"${DOMAIN}","port":"${VMESS_PORT}","id":"${VMESS_UUID}","aid":"0","scy":"auto","net":"ws","type":"none","host":"${DOMAIN}","path":"${VMESS_WS_PATH}","tls":"tls","sni":"${DOMAIN}"}
EOF
)
  printf 'vmess://%s\n' "$(printf '%s' "$json" | base64_one_line)"
}

write_sub_files() {
  local raw_file sub_file html_file clash_file raw_content vless_path_encoded universal_url
  mkdir -p "${APP_WWW}/${SUB_PATH}"
  raw_file="${APP_WWW}/${SUB_PATH}/raw.txt"
  sub_file="${APP_WWW}/${SUB_PATH}/sub.txt"
  html_file="${APP_WWW}/${SUB_PATH}/index.html"
  clash_file="${APP_WWW}/${SUB_PATH}/clash.yaml"
  universal_url="https://${DOMAIN}/${SUB_PATH}/universal"
  vless_path_encoded="${VLESS_WS_PATH//\//%2F}"

  cat >"$raw_file" <<EOF
anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${ANYTLS_PORT}#CTL-AnyTLS
hysteria2://${HY2_PASSWORD}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&insecure=0&obfs=${HY2_OBFS_TYPE}&obfs-password=${HY2_OBFS_PASSWORD}#CTL-Hysteria2
vless://${VLESS_UUID}@${DOMAIN}:${VLESS_PORT}?encryption=none&security=tls&sni=${DOMAIN}&fp=chrome&type=ws&host=${DOMAIN}&path=${vless_path_encoded}#CTL-VLESS-WS
$(ss_uri)
tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&sni=${DOMAIN}&alpn=h3#CTL-TUIC
$(vmess_uri)
EOF

  raw_content="$(cat "$raw_file")"
  printf '%s' "$raw_content" | base64_one_line >"$sub_file"

  cat >"$clash_file" <<EOF
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
ipv6: true
unified-delay: true

proxies:
  - name: "CTL-Hysteria2"
    type: hysteria2
    server: ${DOMAIN}
    port: ${HY2_PORT}
    password: "${HY2_PASSWORD}"
    obfs: ${HY2_OBFS_TYPE}
    obfs-password: "${HY2_OBFS_PASSWORD}"
    sni: ${DOMAIN}
    skip-cert-verify: false
    alpn:
      - h3

  - name: "CTL-TUIC"
    type: tuic
    server: ${DOMAIN}
    port: ${TUIC_PORT}
    uuid: ${TUIC_UUID}
    password: "${TUIC_PASSWORD}"
    udp: true
    sni: ${DOMAIN}
    skip-cert-verify: false
    alpn:
      - h3
    congestion-controller: bbr

  - name: "CTL-Shadowsocks"
    type: ss
    server: ${DOMAIN}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true

  - name: "CTL-VLESS-WS"
    type: vless
    server: ${DOMAIN}
    port: ${VLESS_PORT}
    udp: true
    uuid: ${VLESS_UUID}
    tls: true
    servername: ${DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: ${VLESS_WS_PATH}
      headers:
        Host: ${DOMAIN}

  - name: "CTL-VMess-WS"
    type: vmess
    server: ${DOMAIN}
    port: ${VMESS_PORT}
    udp: true
    uuid: ${VMESS_UUID}
    alterId: 0
    cipher: auto
    tls: true
    servername: ${DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: ${VMESS_WS_PATH}
      headers:
        Host: ${DOMAIN}

proxy-groups:
  - name: "CTL-Select"
    type: select
    proxies:
      - "CTL-Hysteria2"
      - "CTL-TUIC"
      - "CTL-VLESS-WS"
      - "CTL-VMess-WS"
      - "CTL-Shadowsocks"

  - name: "CTL-Auto"
    type: url-test
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    proxies:
      - "CTL-Hysteria2"
      - "CTL-TUIC"
      - "CTL-VLESS-WS"
      - "CTL-VMess-WS"
      - "CTL-Shadowsocks"

rules:
  - GEOIP,CN,DIRECT
  - MATCH,CTL-Select
EOF

  cat >"$html_file" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>CTL Subscription</title>
  <style>
    body { margin: 0; font-family: "Segoe UI","Helvetica Neue",Arial,sans-serif; background: linear-gradient(135deg,#f5f7fb,#edf6ff); color: #10243f; }
    main { max-width: 760px; margin: 0 auto; padding: 48px 20px 64px; }
    .card { background: rgba(255,255,255,.9); border: 1px solid rgba(16,36,63,.08); border-radius: 20px; padding: 22px; box-shadow: 0 12px 40px rgba(16,36,63,.08); margin-top: 18px; }
    a { color: #0a67d0; text-decoration: none; word-break: break-all; }
    code { display: inline-block; padding: 2px 8px; border-radius: 8px; background: #eff5ff; }
  </style>
</head>
<body>
  <main>
    <h1>CTL Subscription</h1>
    <div class="card">
      <p>Universal smart entry: <a href="${universal_url}">${universal_url}</a></p>
      <p>v2rayN base64 subscription: <a href="/${SUB_PATH}/sub.txt">https://${DOMAIN}/${SUB_PATH}/sub.txt</a></p>
      <p>Clash/Mihomo YAML: <a href="/${SUB_PATH}/clash.yaml">https://${DOMAIN}/${SUB_PATH}/clash.yaml</a></p>
      <p>Raw share links: <a href="/${SUB_PATH}/raw.txt">https://${DOMAIN}/${SUB_PATH}/raw.txt</a></p>
      <p>Plain-text node info: <a href="/${SUB_PATH}/client-info.txt">https://${DOMAIN}/${SUB_PATH}/client-info.txt</a></p>
    </div>
    <div class="card">
      <p>Panel command: <code>ctl</code></p>
      <p>Recommended mapping: Clash/Clash Party -> clash.yaml, v2rayN/Shadowrocket -> sub.txt, Karing -> universal or choose the format you prefer.</p>
      <p>Clash-compatible output excludes AnyTLS by design. AnyTLS remains available in the raw/v2ray-style subscription for clients that support it.</p>
    </div>
  </main>
</body>
</html>
EOF
}

write_client_info() {
  local raw_url sub_url clash_url universal_url info_url cert_expire sing_ver vless_path_encoded
  raw_url="https://${DOMAIN}/${SUB_PATH}/raw.txt"
  sub_url="https://${DOMAIN}/${SUB_PATH}/sub.txt"
  clash_url="https://${DOMAIN}/${SUB_PATH}/clash.yaml"
  universal_url="https://${DOMAIN}/${SUB_PATH}/universal"
  info_url="https://${DOMAIN}/${SUB_PATH}/client-info.txt"
  cert_expire="unknown"
  sing_ver="$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 || true)"
  vless_path_encoded="${VLESS_WS_PATH//\//%2F}"
  if [ -f "${CERT_DIR}/fullchain.pem" ]; then
    cert_expire="$(openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')"
  fi
  cat >"$CLIENT_INFO" <<EOF
CTL Deployment Information
===========================
System: ${OS_NAME}
Domain: ${DOMAIN}
Panel command: ctl
sing-box: ${sing_ver}
Certificate expiry: ${cert_expire}

Universal smart entry: ${universal_url}
v2rayN base64 subscription: ${sub_url}
Clash/Mihomo YAML: ${clash_url}
Raw links: ${raw_url}
Plain-text info: ${info_url}

AnyTLS
  host: ${DOMAIN}
  port: ${ANYTLS_PORT}
  password: ${ANYTLS_PASSWORD}
  note: best for sing-box / AnyTLS-capable clients
  uri: anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${ANYTLS_PORT}#CTL-AnyTLS

Hysteria2
  host: ${DOMAIN}
  port: ${HY2_PORT}
  auth: ${HY2_PASSWORD}
  sni: ${DOMAIN}
  obfs: ${HY2_OBFS_TYPE}
  obfs-password: ${HY2_OBFS_PASSWORD}
  uri: hysteria2://${HY2_PASSWORD}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&insecure=0&obfs=${HY2_OBFS_TYPE}&obfs-password=${HY2_OBFS_PASSWORD}#CTL-Hysteria2

VLESS + WS + TLS
  host: ${DOMAIN}
  port: ${VLESS_PORT}
  uuid: ${VLESS_UUID}
  path: ${VLESS_WS_PATH}
  uri: vless://${VLESS_UUID}@${DOMAIN}:${VLESS_PORT}?encryption=none&security=tls&sni=${DOMAIN}&fp=chrome&type=ws&host=${DOMAIN}&path=${vless_path_encoded}#CTL-VLESS-WS

Shadowsocks
  host: ${DOMAIN}
  port: ${SS_PORT}
  method: ${SS_METHOD}
  password: ${SS_PASSWORD}
  uri: $(ss_uri)

TUIC
  host: ${DOMAIN}
  port: ${TUIC_PORT}
  uuid: ${TUIC_UUID}
  password: ${TUIC_PASSWORD}
  sni: ${DOMAIN}
  uri: tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&sni=${DOMAIN}&alpn=h3#CTL-TUIC

VMess + WS + TLS
  host: ${DOMAIN}
  port: ${VMESS_PORT}
  uuid: ${VMESS_UUID}
  path: ${VMESS_WS_PATH}
  uri: $(vmess_uri)
EOF
  cp "$CLIENT_INFO" "${APP_WWW}/${SUB_PATH}/client-info.txt"
  cat >"$META_INFO" <<EOF
{
  "domain": "${DOMAIN}",
  "subscription_universal": "${universal_url}",
  "subscription_base64": "${sub_url}",
  "subscription_clash": "${clash_url}",
  "subscription_raw": "${raw_url}",
  "client_info": "${info_url}"
}
EOF
}

show_sub() {
  load_state
  [ -n "${DOMAIN:-}" ] || fail "No installed configuration was found."
  printf 'Universal smart entry: https://%s/%s/universal\n' "$DOMAIN" "$SUB_PATH"
  printf 'v2rayN base64 subscription: https://%s/%s/sub.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Clash/Mihomo YAML: https://%s/%s/clash.yaml\n' "$DOMAIN" "$SUB_PATH"
  printf 'Raw links: https://%s/%s/raw.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Plain-text info: https://%s/%s/client-info.txt\n' "$DOMAIN" "$SUB_PATH"
}

usage() {
  cat <<EOF
Usage:
  bash ctl.sh
  ctl
  ctl install
  ctl show
  ctl sub
  ctl renew
  ctl update
  ctl restart
  ctl uninstall
  ctl tune-network
  ctl set-update-url https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh

Environment variables:
  CTL_DOMAIN=your.domain.com
  CTL_EMAIL=you@example.com
  CTL_SCRIPT_URL=https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh
  CTL_VLESS_WS_PATH=/ctl-vless
  CTL_VMESS_WS_PATH=/ctl-vmess
  CTL_RESET_SECRETS=1

Notes:
  1. 443/tcp serves the subscription site and the WS+TLS entries for VLESS/VMess.
  2. 443/udp is used by default for Hysteria2.
  3. Clash/Mihomo output excludes AnyTLS on purpose; AnyTLS remains in the raw/base64 subscription for clients that support it.
  4. Use /universal for smart redirects, /clash.yaml for Clash-family clients, and /sub.txt for v2ray-style clients.
  5. Default ports: AnyTLS=${DEFAULT_ANYTLS_PORT} Hysteria2=443/udp Shadowsocks=${SS_PORT} TUIC=${TUIC_PORT} VLESS/VMess=443/tcp
EOF
}

# Client-aware subscription overrides:
# - generic v2ray-style feeds exclude protocols with spotty client support
# - Karing feed can include AnyTLS because Karing officially supports it
# - Clash/Mihomo feed includes only mihomo-supported proxy types
vless_ws_uri() {
  local vless_path_encoded
  vless_path_encoded="${VLESS_WS_PATH//\//%2F}"
  printf 'vless://%s@%s:%s?encryption=none&security=tls&sni=%s&fp=chrome&type=ws&host=%s&path=%s#CTL-VLESS-WS\n' \
    "$VLESS_UUID" "$DOMAIN" "$VLESS_PORT" "$DOMAIN" "$DOMAIN" "$vless_path_encoded"
}

build_common_v2ray_lines() {
  cat <<EOF
hysteria2://${HY2_PASSWORD}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&insecure=0&obfs=${HY2_OBFS_TYPE}&obfs-password=${HY2_OBFS_PASSWORD}#CTL-Hysteria2
$(vless_ws_uri)
$(ss_uri)
tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&sni=${DOMAIN}&alpn=h3#CTL-TUIC
$(vmess_uri)
$(trojan_ws_uri)
$(trojan_grpc_uri)
EOF
}

build_karing_lines() {
  cat <<EOF
anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${ANYTLS_PORT}#CTL-AnyTLS
$(build_common_v2ray_lines)
EOF
}

write_mihomo_yaml() {
  local clash_file="$1"
  cat >"$clash_file" <<EOF
mixed-port: 7890
allow-lan: true
mode: rule
log-level: info
ipv6: true
unified-delay: true
tcp-concurrent: true

dns:
  enable: true
  ipv6: true
  respect-rules: true
  nameserver:
    - https://cloudflare-dns.com/dns-query
    - https://dns.google/dns-query

proxies:
  - name: "CTL-Hysteria2"
    type: hysteria2
    server: ${DOMAIN}
    port: ${HY2_PORT}
    password: "${HY2_PASSWORD}"
    obfs: ${HY2_OBFS_TYPE}
    obfs-password: "${HY2_OBFS_PASSWORD}"
    sni: ${DOMAIN}
    skip-cert-verify: false
    alpn:
      - h3

  - name: "CTL-TUIC"
    type: tuic
    server: ${DOMAIN}
    port: ${TUIC_PORT}
    uuid: ${TUIC_UUID}
    password: "${TUIC_PASSWORD}"
    udp: true
    sni: ${DOMAIN}
    skip-cert-verify: false
    alpn:
      - h3
    congestion-controller: bbr

  - name: "CTL-Shadowsocks"
    type: ss
    server: ${DOMAIN}
    port: ${SS_PORT}
    cipher: ${SS_METHOD}
    password: "${SS_PASSWORD}"
    udp: true

  - name: "CTL-VLESS-WS"
    type: vless
    server: ${DOMAIN}
    port: ${VLESS_PORT}
    udp: true
    uuid: ${VLESS_UUID}
    tls: true
    servername: ${DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: ${VLESS_WS_PATH}
      headers:
        Host: ${DOMAIN}

  - name: "CTL-VMess-WS"
    type: vmess
    server: ${DOMAIN}
    port: ${VMESS_PORT}
    udp: true
    uuid: ${VMESS_UUID}
    alterId: 0
    cipher: auto
    tls: true
    servername: ${DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: ${VMESS_WS_PATH}
      headers:
        Host: ${DOMAIN}

  - name: "CTL-Trojan-WS"
    type: trojan
    server: ${DOMAIN}
    port: 443
    password: "${TROJAN_PASSWORD}"
    udp: true
    sni: ${DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: false
    network: ws
    ws-opts:
      path: ${TROJAN_WS_PATH}
      headers:
        Host: ${DOMAIN}

  - name: "CTL-Trojan-gRPC"
    type: trojan
    server: ${DOMAIN}
    port: 443
    password: "${TROJAN_PASSWORD}"
    udp: true
    sni: ${DOMAIN}
    client-fingerprint: chrome
    skip-cert-verify: false
    network: grpc
    grpc-opts:
      grpc-service-name: ${TROJAN_GRPC_SERVICE}

proxy-groups:
  - name: "CTL-Select"
    type: select
    proxies:
      - "CTL-Auto"
      - "CTL-Trojan-WS"
      - "CTL-Trojan-gRPC"
      - "CTL-VLESS-WS"
      - "CTL-Hysteria2"
      - "CTL-TUIC"
      - "CTL-VMess-WS"
      - "CTL-Shadowsocks"
      - DIRECT

  - name: "CTL-Auto"
    type: url-test
    url: "http://www.gstatic.com/generate_204"
    interval: 300
    proxies:
      - "CTL-Trojan-WS"
      - "CTL-Trojan-gRPC"
      - "CTL-VLESS-WS"
      - "CTL-Hysteria2"
      - "CTL-TUIC"
      - "CTL-VMess-WS"
      - "CTL-Shadowsocks"

  - name: "CTL-AI"
    type: select
    proxies:
      - "CTL-Trojan-WS"
      - "CTL-Trojan-gRPC"
      - "CTL-VLESS-WS"
      - "CTL-Auto"
      - "CTL-Hysteria2"
      - "CTL-TUIC"
      - "CTL-VMess-WS"
      - "CTL-Shadowsocks"

  - name: "CTL-Streaming"
    type: select
    proxies:
      - "CTL-Trojan-WS"
      - "CTL-Trojan-gRPC"
      - "CTL-VLESS-WS"
      - "CTL-Auto"
      - "CTL-Hysteria2"
      - "CTL-TUIC"
      - "CTL-VMess-WS"
      - "CTL-Shadowsocks"

  - name: "CTL-Social"
    type: select
    proxies:
      - "CTL-Trojan-WS"
      - "CTL-Trojan-gRPC"
      - "CTL-VLESS-WS"
      - "CTL-Auto"
      - "CTL-Hysteria2"
      - "CTL-TUIC"
      - "CTL-VMess-WS"
      - "CTL-Shadowsocks"

rules:
  - DOMAIN-SUFFIX,openai.com,CTL-AI
  - DOMAIN-SUFFIX,chatgpt.com,CTL-AI
  - DOMAIN-SUFFIX,oaistatic.com,CTL-AI
  - DOMAIN-SUFFIX,oaiusercontent.com,CTL-AI
  - DOMAIN-SUFFIX,anthropic.com,CTL-AI
  - DOMAIN-SUFFIX,claude.ai,CTL-AI
  - DOMAIN,gemini.google.com,CTL-AI
  - DOMAIN-SUFFIX,perplexity.ai,CTL-AI
  - DOMAIN-SUFFIX,x.ai,CTL-AI
  - DOMAIN-SUFFIX,grok.com,CTL-AI
  - DOMAIN-SUFFIX,netflix.com,CTL-Streaming
  - DOMAIN-SUFFIX,nflxext.com,CTL-Streaming
  - DOMAIN-SUFFIX,nflximg.net,CTL-Streaming
  - DOMAIN-SUFFIX,nflxso.net,CTL-Streaming
  - DOMAIN-SUFFIX,nflxvideo.net,CTL-Streaming
  - DOMAIN-SUFFIX,tiktok.com,CTL-Social
  - DOMAIN-SUFFIX,tiktokv.com,CTL-Social
  - DOMAIN-SUFFIX,byteoversea.com,CTL-Social
  - DOMAIN-SUFFIX,ibytedtos.com,CTL-Social
  - DOMAIN-SUFFIX,facebook.com,CTL-Social
  - DOMAIN-SUFFIX,fbcdn.net,CTL-Social
  - DOMAIN-SUFFIX,instagram.com,CTL-Social
  - DOMAIN-SUFFIX,cdninstagram.com,CTL-Social
  - DOMAIN-SUFFIX,whatsapp.com,CTL-Social
  - DOMAIN-SUFFIX,whatsapp.net,CTL-Social
  - DOMAIN-SUFFIX,x.com,CTL-Social
  - DOMAIN-SUFFIX,twitter.com,CTL-Social
  - DOMAIN-SUFFIX,twimg.com,CTL-Social
  - GEOIP,CN,DIRECT
  - MATCH,CTL-Select
EOF
}

nginx_https() {
  cat >"$NGINX_CONF" <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    root ${APP_WWW};

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};
    root ${APP_WWW};

    ssl_certificate ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    add_header Cache-Control "no-store";

    location /.well-known/acme-challenge/ {
        try_files \$uri =404;
    }

    location = /${SUB_PATH}/universal {
        if (\$arg_client = clash) { return 302 https://\$host/${SUB_PATH}/clash.yaml; }
        if (\$arg_client = clash-party) { return 302 https://\$host/${SUB_PATH}/clash.yaml; }
        if (\$arg_client = mihomo) { return 302 https://\$host/${SUB_PATH}/clash.yaml; }
        if (\$arg_client = v2rayn) { return 302 https://\$host/${SUB_PATH}/v2rayn.txt; }
        if (\$arg_client = shadowrocket) { return 302 https://\$host/${SUB_PATH}/shadowrocket.txt; }
        if (\$arg_client = karing) { return 302 https://\$host/${SUB_PATH}/karing.txt; }
        if (\$arg_client = raw) { return 302 https://\$host/${SUB_PATH}/raw.txt; }

        if (\$arg_format = clash) { return 302 https://\$host/${SUB_PATH}/clash.yaml; }
        if (\$arg_format = v2ray) { return 302 https://\$host/${SUB_PATH}/sub.txt; }
        if (\$arg_format = raw) { return 302 https://\$host/${SUB_PATH}/raw.txt; }

        if (\$http_user_agent ~* "(clash|mihomo|clash-party|clashparty)") { return 302 https://\$host/${SUB_PATH}/clash.yaml; }
        if (\$http_user_agent ~* "(v2rayn)") { return 302 https://\$host/${SUB_PATH}/v2rayn.txt; }
        if (\$http_user_agent ~* "(shadowrocket)") { return 302 https://\$host/${SUB_PATH}/shadowrocket.txt; }
        if (\$http_user_agent ~* "(karing)") { return 302 https://\$host/${SUB_PATH}/karing.txt; }

        return 302 https://\$host/${SUB_PATH}/index.html;
    }

    location = ${VLESS_WS_PATH} {
        proxy_pass http://127.0.0.1:11080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }

    location = ${VMESS_WS_PATH} {
        proxy_pass http://127.0.0.1:12080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }

    location = ${TROJAN_WS_PATH} {
        proxy_pass http://127.0.0.1:13080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }

    location /${TROJAN_GRPC_SERVICE} {
        grpc_set_header Host \$host;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_read_timeout 86400;
        grpc_pass grpc://127.0.0.1:13081;
    }

    location / {
        try_files \$uri \$uri/ /index.html =404;
    }
}
EOF
  nginx -t
  systemctl reload nginx
}

write_sub_files() {
  local raw_file sub_file html_file clash_file v2rayn_file shadowrocket_file karing_file raw_content common_content karing_content universal_url
  mkdir -p "${APP_WWW}/${SUB_PATH}"
  raw_file="${APP_WWW}/${SUB_PATH}/raw.txt"
  sub_file="${APP_WWW}/${SUB_PATH}/sub.txt"
  html_file="${APP_WWW}/${SUB_PATH}/index.html"
  clash_file="${APP_WWW}/${SUB_PATH}/clash.yaml"
  v2rayn_file="${APP_WWW}/${SUB_PATH}/v2rayn.txt"
  shadowrocket_file="${APP_WWW}/${SUB_PATH}/shadowrocket.txt"
  karing_file="${APP_WWW}/${SUB_PATH}/karing.txt"
  universal_url="https://${DOMAIN}/${SUB_PATH}/universal"

  common_content="$(build_common_v2ray_lines)"
  karing_content="$(build_karing_lines)"

  printf '%s\n' "$karing_content" >"$raw_file"
  printf '%s\n' "$common_content" >"$v2rayn_file"
  printf '%s\n' "$common_content" >"$shadowrocket_file"
  printf '%s\n' "$karing_content" >"$karing_file"
  printf '%s\n' "$common_content" >"$sub_file"

  write_mihomo_yaml "$clash_file"

  raw_content="$(cat "$sub_file")"
  printf '%s' "$raw_content" | base64_one_line >"$sub_file.b64"
  mv "$sub_file.b64" "$sub_file"

  cat >"$html_file" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>CTL Subscription</title>
  <style>
    body { margin: 0; font-family: "Segoe UI","Helvetica Neue",Arial,sans-serif; background: linear-gradient(135deg,#f5f7fb,#edf6ff); color: #10243f; }
    main { max-width: 820px; margin: 0 auto; padding: 48px 20px 64px; }
    .card { background: rgba(255,255,255,.9); border: 1px solid rgba(16,36,63,.08); border-radius: 20px; padding: 22px; box-shadow: 0 12px 40px rgba(16,36,63,.08); margin-top: 18px; }
    a { color: #0a67d0; text-decoration: none; word-break: break-all; }
    code { display: inline-block; padding: 2px 8px; border-radius: 8px; background: #eff5ff; }
    ul { margin: 12px 0 0; padding-left: 20px; }
    li { margin: 8px 0; }
  </style>
</head>
<body>
  <main>
    <h1>CTL Subscription Hub</h1>
    <div class="card">
      <p>Universal smart entry: <a href="${universal_url}">${universal_url}</a></p>
      <ul>
        <li>Clash / Clash Party: <a href="/${SUB_PATH}/clash.yaml">https://${DOMAIN}/${SUB_PATH}/clash.yaml</a></li>
        <li>v2rayN: <a href="/${SUB_PATH}/v2rayn.txt">https://${DOMAIN}/${SUB_PATH}/v2rayn.txt</a></li>
        <li>Shadowrocket: <a href="/${SUB_PATH}/shadowrocket.txt">https://${DOMAIN}/${SUB_PATH}/shadowrocket.txt</a></li>
        <li>Karing: <a href="/${SUB_PATH}/karing.txt">https://${DOMAIN}/${SUB_PATH}/karing.txt</a></li>
        <li>Generic v2ray-style: <a href="/${SUB_PATH}/sub.txt">https://${DOMAIN}/${SUB_PATH}/sub.txt</a></li>
        <li>Raw all-protocol links: <a href="/${SUB_PATH}/raw.txt">https://${DOMAIN}/${SUB_PATH}/raw.txt</a></li>
        <li>Plain-text node info: <a href="/${SUB_PATH}/client-info.txt">https://${DOMAIN}/${SUB_PATH}/client-info.txt</a></li>
      </ul>
    </div>
    <div class="card">
      <p>Import guidance:</p>
      <ul>
        <li>Use <code>clash.yaml</code> for Clash-family clients. It now includes <code>CTL-AI</code>, <code>CTL-Streaming</code>, and <code>CTL-Social</code> groups.</li>
        <li>Use <code>v2rayn.txt</code> for v2rayN.</li>
        <li>Use <code>shadowrocket.txt</code> for Shadowrocket.</li>
        <li>Use <code>karing.txt</code> for Karing if you want AnyTLS included.</li>
        <li><code>clash.yaml</code> and the generic <code>sub.txt</code> intentionally exclude AnyTLS to avoid import errors in stricter clients.</li>
        <li>Run <code>ctl site-check</code> on the server if Netflix, TikTok, ChatGPT, Claude, Gemini, or similar sites do not open.</li>
      </ul>
    </div>
  </main>
</body>
</html>
EOF
}

write_client_info() {
  local raw_url sub_url clash_url universal_url v2rayn_url shadowrocket_url karing_url info_url cert_expire sing_ver
  raw_url="https://${DOMAIN}/${SUB_PATH}/raw.txt"
  sub_url="https://${DOMAIN}/${SUB_PATH}/sub.txt"
  clash_url="https://${DOMAIN}/${SUB_PATH}/clash.yaml"
  universal_url="https://${DOMAIN}/${SUB_PATH}/universal"
  v2rayn_url="https://${DOMAIN}/${SUB_PATH}/v2rayn.txt"
  shadowrocket_url="https://${DOMAIN}/${SUB_PATH}/shadowrocket.txt"
  karing_url="https://${DOMAIN}/${SUB_PATH}/karing.txt"
  info_url="https://${DOMAIN}/${SUB_PATH}/client-info.txt"
  cert_expire="unknown"
  sing_ver="$(/usr/local/bin/sing-box version 2>/dev/null | head -n1 || true)"
  if [ -f "${CERT_DIR}/fullchain.pem" ]; then
    cert_expire="$(openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')"
  fi
  cat >"$CLIENT_INFO" <<EOF
CTL Deployment Information
===========================
System: ${OS_NAME}
Domain: ${DOMAIN}
Panel command: ctl
sing-box: ${sing_ver}
Certificate expiry: ${cert_expire}

Universal smart entry: ${universal_url}
Clash / Clash Party: ${clash_url}
v2rayN: ${v2rayn_url}
Shadowrocket: ${shadowrocket_url}
Karing: ${karing_url}
Generic v2ray-style: ${sub_url}
Raw links: ${raw_url}
Plain-text info: ${info_url}

Protocol notes
--------------
AnyTLS is included in Karing and raw outputs only.
The generic v2ray-style feed excludes AnyTLS to reduce import failures in stricter clients.
Clash-family clients receive a Mihomo YAML profile without AnyTLS, but with dedicated AI, streaming, and social groups.

Service reachability notes
--------------------------
Protocol selection does not unlock services by itself. Netflix, TikTok, ChatGPT, Claude, Gemini, and similar platforms care mostly about the VPS egress IP, ASN, region, and reputation.
For login-heavy sites, try this order first: Trojan WS, Trojan gRPC, VLESS WS, then Hysteria2 or TUIC.
Run this on the server when a site fails:
  ctl site-check

AnyTLS
  host: ${DOMAIN}
  port: ${ANYTLS_PORT}
  password: ${ANYTLS_PASSWORD}
  note: included in karing.txt and raw.txt
  uri: anytls://${ANYTLS_PASSWORD}@${DOMAIN}:${ANYTLS_PORT}#CTL-AnyTLS

Hysteria2
  host: ${DOMAIN}
  port: ${HY2_PORT}
  auth: ${HY2_PASSWORD}
  sni: ${DOMAIN}
  obfs: ${HY2_OBFS_TYPE}
  obfs-password: ${HY2_OBFS_PASSWORD}
  uri: hysteria2://${HY2_PASSWORD}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&insecure=0&obfs=${HY2_OBFS_TYPE}&obfs-password=${HY2_OBFS_PASSWORD}#CTL-Hysteria2

VLESS + WS + TLS
  host: ${DOMAIN}
  port: ${VLESS_PORT}
  uuid: ${VLESS_UUID}
  path: ${VLESS_WS_PATH}
  uri: $(vless_ws_uri)

Shadowsocks
  host: ${DOMAIN}
  port: ${SS_PORT}
  method: ${SS_METHOD}
  password: ${SS_PASSWORD}
  uri: $(ss_uri)

TUIC
  host: ${DOMAIN}
  port: ${TUIC_PORT}
  uuid: ${TUIC_UUID}
  password: ${TUIC_PASSWORD}
  sni: ${DOMAIN}
  uri: tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${DOMAIN}:${TUIC_PORT}?congestion_control=bbr&sni=${DOMAIN}&alpn=h3#CTL-TUIC

VMess + WS + TLS
  host: ${DOMAIN}
  port: ${VMESS_PORT}
  uuid: ${VMESS_UUID}
  path: ${VMESS_WS_PATH}
  uri: $(vmess_uri)

Trojan + WS + TLS
  host: ${DOMAIN}
  port: 443
  password: ${TROJAN_PASSWORD}
  path: ${TROJAN_WS_PATH}
  uri: $(trojan_ws_uri)

Trojan + gRPC + TLS
  host: ${DOMAIN}
  port: 443
  password: ${TROJAN_PASSWORD}
  service: ${TROJAN_GRPC_SERVICE}
  uri: $(trojan_grpc_uri)
EOF
  cp "$CLIENT_INFO" "${APP_WWW}/${SUB_PATH}/client-info.txt"
  cat >"$META_INFO" <<EOF
{
  "domain": "${DOMAIN}",
  "subscription_universal": "${universal_url}",
  "subscription_clash": "${clash_url}",
  "subscription_v2rayn": "${v2rayn_url}",
  "subscription_shadowrocket": "${shadowrocket_url}",
  "subscription_karing": "${karing_url}",
  "subscription_base64": "${sub_url}",
  "subscription_raw": "${raw_url}",
  "client_info": "${info_url}"
}
EOF
}

show_sub() {
  load_state
  [ -n "${DOMAIN:-}" ] || fail "No installed configuration was found."
  printf 'Universal smart entry: https://%s/%s/universal\n' "$DOMAIN" "$SUB_PATH"
  printf 'Clash / Clash Party: https://%s/%s/clash.yaml\n' "$DOMAIN" "$SUB_PATH"
  printf 'v2rayN: https://%s/%s/v2rayn.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Shadowrocket: https://%s/%s/shadowrocket.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Karing: https://%s/%s/karing.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Generic v2ray-style: https://%s/%s/sub.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Raw links: https://%s/%s/raw.txt\n' "$DOMAIN" "$SUB_PATH"
  printf 'Plain-text info: https://%s/%s/client-info.txt\n' "$DOMAIN" "$SUB_PATH"
}

http_probe_code() {
  local url="$1"
  local ua code
  ua="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
  code="$(curl -4 -A "$ua" -sS -L --connect-timeout 8 --max-time 20 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
  printf '%s\n' "${code:-000}"
}

print_probe_result() {
  local name="$1"
  local state="$2"
  local detail="$3"
  printf '%-18s %-9s %s\n' "$name" "$state" "$detail"
}

probe_generic_site() {
  local name="$1"
  local url="$2"
  local code state detail
  code="$(http_probe_code "$url")"
  case "$code" in
    200|204|301|302|307|308)
      state="OK"
      detail="reachable"
      ;;
    401)
      state="OK"
      detail="reachable, authentication required"
      ;;
    403)
      state="LIMITED"
      detail="HTTP 403, reachable but challenged or region-limited"
      ;;
    000)
      state="FAIL"
      detail="request failed or timed out"
      ;;
    *)
      state="CHECK"
      detail="HTTP ${code}"
      ;;
  esac
  print_probe_result "$name" "$state" "$detail"
}

probe_netflix_site() {
  local code state detail
  code="$(http_probe_code 'https://www.netflix.com/title/81215567')"
  case "$code" in
    200)
      state="OK"
      detail="full catalog likely available"
      ;;
    404)
      state="PARTIAL"
      detail="Netflix Originals only is likely"
      ;;
    403)
      state="FAIL"
      detail="blocked or unsupported by the current IP"
      ;;
    000)
      state="FAIL"
      detail="request failed or timed out"
      ;;
    *)
      state="CHECK"
      detail="HTTP ${code}"
      ;;
  esac
  print_probe_result "Netflix" "$state" "$detail"
}

site_check() {
  local ip
  load_state
  [ -f "$STATE_FILE" ] || fail "No installed configuration was found."
  ip="$(public_ipv4)"

  printf 'CTL site reachability check\n'
  printf '============================\n'
  if [ -n "$ip" ]; then
    printf 'Current VPS IPv4: %s\n' "$ip"
  fi
  printf '\n'
  printf 'AI services\n'
  printf '-----------\n'
  probe_generic_site "ChatGPT Web" "https://chatgpt.com/"
  probe_generic_site "OpenAI API" "https://api.openai.com/v1/models"
  probe_generic_site "Claude" "https://claude.ai/login"
  probe_generic_site "Gemini" "https://gemini.google.com/app"
  probe_generic_site "Perplexity" "https://www.perplexity.ai/"
  printf '\n'
  printf 'Streaming / social\n'
  printf '------------------\n'
  probe_netflix_site
  probe_generic_site "TikTok" "https://www.tiktok.com/"
  probe_generic_site "Facebook" "https://www.facebook.com/"
  probe_generic_site "X" "https://x.com/"
  printf '\n'
  printf 'Notes\n'
  printf '-----\n'
  printf '%s\n' "1. This check reflects the VPS egress IP, not a specific protocol."
  printf '%s\n' "2. If a service fails here, switching between Hysteria2, TUIC, VLESS, VMess, or Trojan usually will not fix it."
  printf '%s\n' "3. For login-heavy sites, try Trojan WS, Trojan gRPC, or VLESS WS first."
  printf '%s\n' "4. Netflix, TikTok, ChatGPT, Claude, and Gemini are strongly affected by IP reputation, ASN type, and region."
}

usage() {
  cat <<EOF
Usage:
  bash ctl.sh
  ctl
  ctl install
  ctl show
  ctl sub
  ctl renew
  ctl update
  ctl restart
  ctl uninstall
  ctl site-check
  ctl tune-network
  ctl set-update-url https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh

Environment variables:
  CTL_DOMAIN=your.domain.com
  CTL_EMAIL=you@example.com
  CTL_SCRIPT_URL=https://raw.githubusercontent.com/cimile/ctl/main/ctl.sh
  CTL_VLESS_WS_PATH=/ctl-vless
  CTL_VMESS_WS_PATH=/ctl-vmess
  CTL_TROJAN_WS_PATH=/ctl-trojan-ws
  CTL_TROJAN_GRPC_SERVICE=ctl-trojan-grpc
  CTL_RESET_SECRETS=1

Notes:
  1. 443/tcp serves the subscription site plus the WS+TLS entries for VLESS, VMess, and Trojan, and the Trojan gRPC endpoint.
  2. 443/udp is used by default for Hysteria2.
  3. Client-specific subscriptions are generated to reduce import errors.
  4. Use /clash.yaml for Clash-family clients, /v2rayn.txt for v2rayN, /shadowrocket.txt for Shadowrocket, /karing.txt for Karing, and /universal for smart redirects.
  5. AnyTLS is excluded from Clash and generic v2ray-style feeds, and kept only in Karing and raw outputs.
  6. Run ctl site-check if Netflix, TikTok, ChatGPT, Claude, Gemini, or similar sites fail to open.
EOF
}

main() {
  local action="${1:-menu}"
  case "$action" in
    menu) need_root; loop_menu ;;
    install|reinstall) install_all ;;
    show|info) show_info ;;
    sub|subscription) show_sub ;;
    renew) renew_cert ;;
    update|sync-update) update_all ;;
    update-core) update_core ;;
    update-panel) update_panel "${2:-}" ;;
    site-check|unlock-check|check-sites) site_check ;;
    tune-network) sysctl_tune ;;
    set-update-url) set_update_url "${2:-}" ;;
    restart) restart_all ;;
    uninstall) uninstall_all ;;
    help|-h|--help) usage ;;
    *) usage; exit 1 ;;
  esac
}

main "${1:-menu}" "${2:-}"
