#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=modules/00_common.sh
source "${SCRIPT_DIR}/modules/00_common.sh"
source "${SCRIPT_DIR}/modules/01_base_tools.sh"
source "${SCRIPT_DIR}/modules/02_sysctl_bbr_ipv6.sh"
source "${SCRIPT_DIR}/modules/03_ufw.sh"
source "${SCRIPT_DIR}/modules/04_ssh_hardening.sh"
source "${SCRIPT_DIR}/modules/05_nginx.sh"
source "${SCRIPT_DIR}/modules/06_acme.sh"
source "${SCRIPT_DIR}/modules/07_xray.sh"
source "${SCRIPT_DIR}/modules/08_fail2ban.sh"
source "${SCRIPT_DIR}/modules/09_backup.sh"

usage() {
  cat <<USAGE
xray-vps-onekey ${PROJECT_VERSION}

用法:
  bash install.sh [选项]

  不传 --domain:  直连模式（仅 Reality，Xray 监听 0.0.0.0:443，无需 nginx/acme）
  传 --domain:    双模式（Reality + VLESS WS CDN，nginx SNI 分流 443）

CDN/WS 证书（仅双模式需要）:
  --domain DOMAIN              CDN/WS 域名，例如 ws2.example.com
  --cf-key KEY                 Cloudflare Global API Key
  --cf-email EMAIL             Cloudflare 账户邮箱

推荐的 API Token 方式:
  --cf-token TOKEN             Cloudflare API Token
  --cf-zone-id ZONE_ID         Cloudflare Zone ID
  --cf-account-id ACCOUNT_ID   Cloudflare Account ID

选项:
  --ssh-port PORT              SSH 端口，默认 48121
  --ssh-hardening              启用 SSH 加固（改端口 + 限制 root 登录），默认不启用
  --strict-ssh                 配合 --ssh-hardening 使用，禁用密码登录
  --ws-path PATH               WebSocket 路径，默认 /gl2025ws
  --reality-dest DOMAIN        Reality dest/SNI，默认 www.microsoft.com
  --acme-email EMAIL           acme.sh 账户邮箱
  --renew-cert                 强制续签证书
  --skip-acme                  跳过 acme.sh/证书签发（高级用户）
  --skip-backup                跳过安装前配置快照备份
  --help                       显示此帮助

示例:
  # 直连模式（无需域名）
  bash install.sh

  # 双模式 + Cloudflare Global Key
  bash install.sh --domain ws2.example.com --cf-key "xxx" --cf-email "you@example.com"

  # 双模式 + Cloudflare API Token
  bash install.sh --domain ws2.example.com --cf-token "xxx" --cf-zone-id "xxx" --cf-account-id "xxx"

  # 从直连模式无缝升级到双模式
  bash install.sh --domain ws2.example.com --cf-key "xxx" --cf-email "you@example.com"
USAGE
}

parse_args() {
  SSH_PORT="$DEFAULT_SSH_PORT"
  WS_PATH="$DEFAULT_WS_PATH"
  REALITY_DEST="$DEFAULT_REALITY_DEST"
  REALITY_SERVER_NAMES="$DEFAULT_REALITY_SERVER_NAMES"
  XRAY_REALITY_PORT="$DEFAULT_REALITY_PORT"
  XRAY_WS_PORT="$DEFAULT_WS_PORT"
  NGINX_WS_PORT="$DEFAULT_NGINX_WS_PORT"
  STRICT_SSH="false"
  SSH_HARDENING="false"
  RENEW_CERT="false"
  SKIP_ACME="false"
  SKIP_BACKUP="false"
  DOMAIN=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain) DOMAIN="$2"; shift 2 ;;
      --cf-key|--cf_key) CF_Key="$2"; shift 2 ;;
      --cf-email|--cf_email) CF_Email="$2"; shift 2 ;;
      --cf-token|--cf_token) CF_Token="$2"; shift 2 ;;
      --cf-zone-id|--cf_zone_id) CF_Zone_ID="$2"; shift 2 ;;
      --cf-account-id|--cf_account_id) CF_Account_ID="$2"; shift 2 ;;
      --ssh-port) SSH_PORT="$2"; shift 2 ;;
      --ssh-hardening) SSH_HARDENING="true"; shift ;;
      --strict-ssh) STRICT_SSH="true"; shift ;;
      --ws-path) WS_PATH="$2"; shift 2 ;;
      --reality-dest) REALITY_DEST="$2"; REALITY_SERVER_NAMES="[\"$2\"]"; shift 2 ;;
      --acme-email) ACME_EMAIL="$2"; shift 2 ;;
      --renew-cert) RENEW_CERT="true"; shift ;;
      --skip-acme) SKIP_ACME="true"; shift ;;
      --skip-backup) SKIP_BACKUP="true"; shift ;;
      --help|-h) usage; exit 0 ;;
      *) fail "未知选项: $1" ;;
    esac
  done

  if [[ -z "$DOMAIN" ]]; then
    info "未提供 --domain，将安装直连模式（仅 Reality）。"
    info "后续可无缝升级到双模式: bash install.sh --domain xxx --cf-key xxx --cf-email xxx"
  fi
}

persist_config() {
  local server_ip
  server_ip="$(curl -4fsS https://api.ipify.org 2>/dev/null || true)"
  save_kv "$STATE_FILE" PROJECT_VERSION "$PROJECT_VERSION"
  save_kv "$STATE_FILE" SSH_PORT "$SSH_PORT"
  save_kv "$STATE_FILE" DOMAIN "$DOMAIN"
  save_kv "$STATE_FILE" WS_PATH "$WS_PATH"
  save_kv "$STATE_FILE" REALITY_DEST "$REALITY_DEST"
  save_kv "$STATE_FILE" REALITY_SERVER_NAMES "$REALITY_SERVER_NAMES"
  save_kv "$STATE_FILE" XRAY_REALITY_PORT "$XRAY_REALITY_PORT"
  save_kv "$STATE_FILE" XRAY_WS_PORT "$XRAY_WS_PORT"
  save_kv "$STATE_FILE" NGINX_WS_PORT "$NGINX_WS_PORT"
  save_kv "$STATE_FILE" SERVER_IP "$server_ip"

  [[ -n "${CF_Key:-}" ]] && save_kv "$SECRETS_FILE" CF_Key "$CF_Key" || true
  [[ -n "${CF_Email:-}" ]] && save_kv "$SECRETS_FILE" CF_Email "$CF_Email" || true
  [[ -n "${CF_Token:-}" ]] && save_kv "$SECRETS_FILE" CF_Token "$CF_Token" || true
  [[ -n "${CF_Zone_ID:-}" ]] && save_kv "$SECRETS_FILE" CF_Zone_ID "$CF_Zone_ID" || true
  [[ -n "${CF_Account_ID:-}" ]] && save_kv "$SECRETS_FILE" CF_Account_ID "$CF_Account_ID" || true
  [[ -n "${ACME_EMAIL:-}" ]] && save_kv "$STATE_FILE" ACME_EMAIL "$ACME_EMAIL" || true
}

write_summary() {
  load_state
  local private_key_masked cf_masked
  private_key_masked="$(mask_value "${REALITY_PRIVATE_KEY:-}")"
  cf_masked="$(mask_value "${CF_Key:-${CF_Token:-}}")"

  cat > "$PUBLIC_SUMMARY" <<SUMMARY
xray-vps-onekey 公开摘要
版本: ${PROJECT_VERSION}
模式: ${DOMAIN:+双模式}${DOMAIN:-直连模式}
域名: ${DOMAIN:-未设置}
SSH 端口: ${SSH_PORT}
公网入口端口: 443
Reality 本地端口: ${DOMAIN:+${XRAY_REALITY_PORT}}${DOMAIN:-443（直连）}
WS 本地端口: ${DOMAIN:+${XRAY_WS_PORT}}${DOMAIN:-不适用}
Nginx WS 本地端口: ${DOMAIN:+${NGINX_WS_PORT}}${DOMAIN:-不适用}
WS 路径: ${WS_PATH}
Reality dest: ${REALITY_DEST}
UUID: $(mask_value "${XRAY_UUID:-}")
Reality 公钥: $(mask_value "${REALITY_PUBLIC_KEY:-}")
Reality 私钥: ${private_key_masked}
Cloudflare 凭据: ${cf_masked}
SUMMARY
  chmod 644 "$PUBLIC_SUMMARY"

  {
    echo "xray-vps-onekey 私有摘要"
    echo "生成时间: $(date '+%F %T')"
    echo
    "${SCRIPT_DIR}/scripts/print-links.sh"
  } > "$PRIVATE_SUMMARY"
  chmod 600 "$PRIVATE_SUMMARY"
}

main() {
  parse_args "$@"
  require_root
  ensure_state_dir
  persist_config
  "${SCRIPT_DIR}/checks/preflight.sh"
  load_state

  if [[ "$SKIP_BACKUP" != "true" ]]; then
    backup_existing_configs
  else
    warn "已跳过安装前备份，现有配置不会被快照。"
  fi

  install_base_tools
  configure_ufw
  if [[ "$SSH_HARDENING" == "true" ]]; then
    configure_ssh_hardening
  else
    info "未启用 SSH 加固（默认）。如需启用请加 --ssh-hardening。"
  fi
  configure_sysctl_bbr_ipv6

  if [[ -n "$DOMAIN" ]]; then
    info "双模式: Reality 直连 + VLESS WebSocket CDN。"
    install_configure_nginx
    if [[ "$SKIP_ACME" != "true" ]]; then
      install_issue_cert
    else
      warn "已跳过 acme.sh/证书签发。请确保证书文件在 nginx reload 前已存在。"
    fi
    install_xray
    generate_xray_secrets
    render_xray_config
    render_nginx_configs
  else
    info "直连模式: 仅 Reality，Xray 监听 0.0.0.0:443（无需 nginx/acme）。"
    install_xray
    generate_xray_secrets
    render_xray_config
  fi

  configure_fail2ban
  "${SCRIPT_DIR}/checks/doctor.sh"
  write_summary

  success "安装完成。"
  echo
  echo "公开摘要:  ${PUBLIC_SUMMARY}"
  echo "私有摘要:  ${PRIVATE_SUMMARY}"
  echo
  "${SCRIPT_DIR}/scripts/print-links.sh"
}

main "$@"
