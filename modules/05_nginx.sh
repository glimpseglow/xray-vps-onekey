#!/usr/bin/env bash
set -Eeuo pipefail

install_configure_nginx() {
  info "正在安装 nginx-full..."
  apt-get install -y nginx-full

  if ! nginx -V 2>&1 | grep -q -- '--with-stream_ssl_preread_module'; then
    warn "nginx -V 未检测到 --with-stream_ssl_preread_module。Debian 的 nginx-full 通常已支持，最终以 nginx -t 为准。"
  fi

  mkdir -p /etc/nginx/stream-enabled /etc/nginx/sites-available /etc/nginx/sites-enabled

  # 确保 nginx.conf 里有 stream {} 块并 include stream-enabled
  # 1. 先清理之前可能写入的错误裸 include 行（不在 stream {} 块内的）
  if grep -qE '^[[:space:]]*include[[:space:]]+/etc/nginx/stream-enabled' /etc/nginx/nginx.conf 2>/dev/null; then
    if ! grep -qE '^[[:space:]]*stream[[:space:]]*\{' /etc/nginx/nginx.conf 2>/dev/null; then
      # 没有 stream 块，那 include 行一定是错的，删掉
      backup_file /etc/nginx/nginx.conf
      sed -i '/include \/etc\/nginx\/stream-enabled/d' /etc/nginx/nginx.conf
      info "已清理旧的错误 stream-enabled include 行。"
    fi
  fi

  # 2. 确保 stream {} 块存在且包含 include
  if ! grep -qE '^[[:space:]]*stream[[:space:]]*\{' /etc/nginx/nginx.conf 2>/dev/null; then
    backup_file /etc/nginx/nginx.conf
    cat >> /etc/nginx/nginx.conf <<'CONF'

# Managed by xray-vps-onekey
stream {
    include /etc/nginx/stream-enabled/*.conf;
}
CONF
    info "已在 nginx.conf 添加 stream {} 块。"
  elif ! grep -q 'stream-enabled' /etc/nginx/nginx.conf 2>/dev/null; then
    # 有 stream 块但没有 include
    sed -i '/^[[:space:]]*stream[[:space:]]*{/a\    include /etc/nginx/stream-enabled/*.conf;' /etc/nginx/nginx.conf
    info "已在 stream {} 块内添加 include。"
  fi

  systemctl enable nginx >/dev/null
  success "nginx-full 安装完成。"
}

render_nginx_configs() {
  local domain="${DOMAIN:?DOMAIN is required}"
  local ws_path="${WS_PATH:-$DEFAULT_WS_PATH}"
  local nginx_ws_port="${NGINX_WS_PORT:-$DEFAULT_NGINX_WS_PORT}"
  local reality_port="${XRAY_REALITY_PORT:-$DEFAULT_REALITY_PORT}"
  local ws_port="${XRAY_WS_PORT:-$DEFAULT_WS_PORT}"

  info "正在渲染 nginx stream 和 WS 配置..."

  write_file /etc/nginx/stream-enabled/xray-vps-onekey.conf \
    "$(render_template "${TEMPLATE_DIR}/nginx/nginx.conf.stream.tpl" \
       "DOMAIN=${domain}" "NGINX_WS_PORT=${nginx_ws_port}" "XRAY_REALITY_PORT=${reality_port}")"

  write_file "/etc/nginx/sites-available/xray-vps-onekey-ws.conf" \
    "$(render_template "${TEMPLATE_DIR}/nginx/ws-site.conf.tpl" \
       "DOMAIN=${domain}" "NGINX_WS_PORT=${nginx_ws_port}" "XRAY_WS_PORT=${ws_port}" "WS_PATH=${ws_path}")"

  ln -sf /etc/nginx/sites-available/xray-vps-onekey-ws.conf /etc/nginx/sites-enabled/xray-vps-onekey-ws.conf
  nginx -t
  systemctl reload nginx || systemctl restart nginx
  success "nginx 配置已生效。"
}
