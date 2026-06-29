#!/usr/bin/env bash
set -Eeuo pipefail

configure_ufw() {
  local ssh_port="${SSH_PORT:-$DEFAULT_SSH_PORT}"
  info "正在配置 UFW 防火墙..."
  apt-get install -y ufw
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${ssh_port}/tcp" comment 'SSH 自定义端口'
  ufw allow 80/tcp comment 'HTTP 用于 ACME/引导'
  ufw allow 443/tcp comment 'HTTPS/Xray 入口'
  yes | ufw enable >/dev/null || true
  ufw reload >/dev/null || true
  success "UFW 防火墙配置完成。"
}
