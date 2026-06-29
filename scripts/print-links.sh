#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../modules/00_common.sh
source "${SCRIPT_DIR}/modules/00_common.sh"
load_state

urlencode_path() {
  local s="$1"
  python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$s"
}

print_links() {
  local domain="${DOMAIN:-}"
  local server_ip="${SERVER_IP:-$(curl -4fsS https://api.ipify.org 2>/dev/null || true)}"
  local ws_path="${WS_PATH:-$DEFAULT_WS_PATH}"
  local reality_dest="${REALITY_DEST:-$DEFAULT_REALITY_DEST}"
  local encoded_path
  encoded_path="$(urlencode_path "$ws_path")"

  [[ -n "${XRAY_UUID:-}" ]] || fail "未找到 XRAY_UUID，请先运行安装器。"
  [[ -n "${REALITY_PUBLIC_KEY:-}" ]] || fail "未找到 REALITY_PUBLIC_KEY，请先运行安装器。"
  [[ -n "${REALITY_SHORT_ID:-}" ]] || fail "未找到 REALITY_SHORT_ID，请先运行安装器。"

  local reality_link="vless://${XRAY_UUID}@${server_ip}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${reality_dest}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#Reality-Direct"

  echo "Reality 直连链接:"
  echo "$reality_link"
  echo

  if [[ -n "$domain" ]]; then
    local ws_link="vless://${XRAY_UUID}@${domain}:443?encryption=none&security=tls&sni=${domain}&fp=chrome&type=ws&host=${domain}&path=${encoded_path}#CDN-WS"
    echo "CDN WebSocket 链接:"
    echo "$ws_link"
  else
    warn "未配置域名，未生成 CDN WebSocket 链接。"
    warn "配置域名后重跑可升级到双模式: bash install.sh --domain xxx --cf-key xxx --cf-email xxx"
  fi
}

print_links "$@"
