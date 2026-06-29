#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_NAME="xray-vps-onekey"
PROJECT_VERSION="0.1.0"
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/templates"
STATE_DIR="/etc/${PROJECT_NAME}"
STATE_FILE="${STATE_DIR}/state.env"
SECRETS_FILE="${STATE_DIR}/secrets.env"
PUBLIC_SUMMARY="${STATE_DIR}/install-summary.public"
PRIVATE_SUMMARY="${STATE_DIR}/install-summary.private"
BACKUP_DIR="${STATE_DIR}/backups"
LOG_FILE="/var/log/${PROJECT_NAME}.log"

DEFAULT_SSH_PORT="48121"
DEFAULT_DOMAIN=""
DEFAULT_WS_PATH="/gl2025ws"
DEFAULT_REALITY_DEST="www.microsoft.com"
DEFAULT_REALITY_SERVER_NAMES='["www.microsoft.com","microsoft.com"]'
DEFAULT_REALITY_PORT="10443"
DEFAULT_WS_PORT="20443"
DEFAULT_NGINX_WS_PORT="8080"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  local msg="$*"
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '[%s] %s\n' "$(date '+%F %T')" "$msg" \
    | sed -E 's/(CF_Key|CF_Token|REALITY_PRIVATE_KEY|XRAY_UUID|REALITY_SHORT_ID)=([^[:space:]]+)/\1=[REDACTED]/g' \
    >> "$LOG_FILE" 2>/dev/null || true
}

info() { printf "${BLUE}[信息]${NC} %s\n" "$*"; log "INFO $*"; }
success() { printf "${GREEN}[成功]${NC} %s\n" "$*"; log "OK $*"; }
warn() { printf "${YELLOW}[警告]${NC} %s\n" "$*"; log "WARN $*"; }
fail() { printf "${RED}[失败]${NC} %s\n" "$*"; log "FAIL $*"; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "请以 root 用户运行本脚本。"
  fi
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR" "$BACKUP_DIR"
  chmod 700 "$STATE_DIR"
  touch "$STATE_FILE" "$SECRETS_FILE"
  chmod 600 "$STATE_FILE" "$SECRETS_FILE"
}

backup_file() {
  local file="$1"
  [[ -e "$file" ]] || return 0
  ensure_state_dir
  local safe_name
  safe_name="$(echo "$file" | sed 's#/#_#g')"
  cp -a "$file" "${BACKUP_DIR}/${safe_name}.$(date '+%Y%m%d%H%M%S').bak"
}

save_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  ensure_state_dir
  if grep -qE "^${key}=" "$file" 2>/dev/null; then
    sed -i "s#^${key}=.*#${key}='${value}'#" "$file"
  else
    printf "%s='%s'\n" "$key" "$value" >> "$file"
  fi
}

load_state() {
  ensure_state_dir
  # shellcheck disable=SC1090
  source "$STATE_FILE" || true
  # shellcheck disable=SC1090
  source "$SECRETS_FILE" || true
}

port_in_use() {
  local port="$1"
  ss -tulnp 2>/dev/null | awk '{print $5}' | grep -qE "(:|\])${port}$"
}

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

random_hex() {
  openssl rand -hex "$1"
}

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

mask_value() {
  local v="$1"
  local n=${#v}
  if [[ $n -le 8 ]]; then
    printf '[已脱敏]'
  else
    printf '%s****%s' "${v:0:4}" "${v: -4}"
  fi
}

write_file() {
  local path="$1"
  local content="$2"
  local mode="${3:-644}"
  backup_file "$path"
  install -m "$mode" -o root -g root /dev/null "$path"
  printf '%s\n' "$content" > "$path"
}

write_file_600() {
  write_file "$1" "$2" 600
}

render_template() {
  local tpl="$1"
  shift
  [[ -f "$tpl" ]] || fail "模板文件不存在: $tpl"
  local content
  content="$(cat "$tpl")"
  local key value
  for kv in "$@"; do
    key="${kv%%=*}"
    value="${kv#*=}"
    content="${content//\{\{${key}\}\}/${value}}"
  done
  printf '%s\n' "$content"
}
