#!/usr/bin/env bash
set -Eeuo pipefail

install_issue_cert() {
  local domain="${DOMAIN:?DOMAIN is required}"
  local cert_dir="/etc/nginx/ssl/${domain}"
  local acme_sh="/root/.acme.sh/acme.sh"
  local acme_email="${ACME_EMAIL:-admin@${domain}}"
  info "正在安装 acme.sh 并为 ${domain} 签发证书..."

  if [[ ! -x "$acme_sh" ]]; then
    curl -fsSL https://get.acme.sh | sh -s email="${acme_email}"
  else
    info "acme.sh 已安装。"
  fi

  export CF_Key="${CF_Key:-${CF_KEY:-}}"
  export CF_Email="${CF_Email:-${CF_EMAIL:-}}"
  export CF_Token="${CF_Token:-${CF_TOKEN:-}}"
  export CF_Account_ID="${CF_Account_ID:-${CF_ACCOUNT_ID:-}}"
  export CF_Zone_ID="${CF_Zone_ID:-${CF_ZONE_ID:-}}"

  if [[ -z "${CF_Token}" && ( -z "${CF_Key}" || -z "${CF_Email}" ) ]]; then
    fail "需要 Cloudflare 凭据。推荐使用 --cf-token + --cf-zone-id，或使用 --cf-key + --cf-email。"
  fi

  # 注册账户
  info "正在注册 acme.sh 账户..."
  "$acme_sh" --register-account -m "$acme_email" 2>&1 || true

  mkdir -p "$cert_dir"
  chmod 700 "$cert_dir"

  # 1. 先检查目标路径证书文件是否已存在（非 --renew-cert 时直接跳过）
  if [[ -f "${cert_dir}/fullchain.cer" && -f "${cert_dir}/private.key" && "${RENEW_CERT:-false}" != "true" ]]; then
    success "证书已存在: ${cert_dir}/fullchain.cer，跳过签发。"
    chmod 600 "${cert_dir}/private.key"
    return 0
  fi

  # 2. 检查 acme.sh 是否已经真正签发过该域名的证书
  # acme.sh --list 输出格式: Main_Domain  KeyLength  SAN_Domains  Profile  CA  Created  Renew
  # 只有 Created 列有日期才算真正签发成功
  local already_issued="false"
  local list_output
  list_output="$("$acme_sh" --list 2>/dev/null || true)"
  if echo "$list_output" | awk -v d="$domain" '$1==d && $6!="" && $6!="Created" {found=1} END{exit !found}'; then
    already_issued="true"
    local created_date
    created_date="$(echo "$list_output" | awk -v d="$domain" '$1==d {print $6}')"
    info "acme.sh 已有 ${domain} 的证书（创建于 ${created_date}），直接安装。"
  fi

  if [[ "$already_issued" == "true" && "${RENEW_CERT:-false}" != "true" ]]; then
    # 证书已签发，只需安装到 nginx 目录
    info "正在安装证书到 ${cert_dir}..."
    "$acme_sh" --install-cert -d "$domain" --ecc \
      --key-file       "${cert_dir}/private.key" \
      --fullchain-file "${cert_dir}/fullchain.cer" \
      --reloadcmd      "systemctl reload nginx" 2>&1 || true
  else
    if [[ "${RENEW_CERT:-false}" == "true" ]]; then
      info "强制续签证书..."
      "$acme_sh" --renew -d "$domain" --ecc --force --dnssleep 60 2>&1 || true
    else
      info "正在签发证书（DNS 验证，等待 60 秒）..."
      "$acme_sh" --issue --dns dns_cf -d "$domain" --dnssleep 60 \
        --key-file       "${cert_dir}/private.key" \
        --fullchain-file "${cert_dir}/fullchain.cer" 2>&1 || true
    fi
    # issue/renew 失败后尝试 install-cert（有时证书已签发但安装步骤失败）
    if [[ ! -f "${cert_dir}/fullchain.cer" ]]; then
      info "尝试安装已有证书..."
      "$acme_sh" --install-cert -d "$domain" --ecc \
        --key-file       "${cert_dir}/private.key" \
        --fullchain-file "${cert_dir}/fullchain.cer" \
        --reloadcmd      "systemctl reload nginx" 2>&1 || true
    fi
  fi

  chmod 600 "${cert_dir}/private.key" 2>/dev/null || true

  # 验证证书文件
  if [[ -f "${cert_dir}/fullchain.cer" && -f "${cert_dir}/private.key" ]]; then
    success "证书已安装: ${domain}。"
  else
    fail "证书安装失败，证书文件不存在。
可能原因:
  1. CA 对该域名限流（retryafter=86400），需等 24 小时后用 --renew-cert 重试
  2. DNS 验证失败，检查 Cloudflare 凭据是否正确
  3. 域名未托管在 Cloudflare

可用命令排查:
  $acme_sh --list
  $acme_sh --issue --dns dns_cf -d $domain --dnssleep 60 --debug 2
"
  fi
}
