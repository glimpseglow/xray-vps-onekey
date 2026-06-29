#!/usr/bin/env bash
set -Eeuo pipefail

install_configure_nginx() {
  info "正在安装 nginx-full..."
  apt-get install -y nginx-full

  if ! nginx -V 2>&1 | grep -q -- '--with-stream_ssl_preread_module'; then
    warn "nginx -V 未检测到 --with-stream_ssl_preread_module。Debian 的 nginx-full 通常已支持，最终以 nginx -t 为准。"
  fi

  mkdir -p /etc/nginx/stream-enabled /etc/nginx/sites-available /etc/nginx/sites-enabled

  if ! grep -q 'stream-enabled' /etc/nginx/nginx.conf; then
    backup_file /etc/nginx/nginx.conf
    cat >> /etc/nginx/nginx.conf <<'CONF'

# Managed by xray-vps-onekey
include /etc/nginx/stream-enabled/*.conf;
CONF
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
