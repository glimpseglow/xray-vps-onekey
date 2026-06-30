#!/usr/bin/env bash
set -Eeuo pipefail

configure_ufw() {
  local ssh_port="${SSH_PORT:-$DEFAULT_SSH_PORT}"
  info "正在配置 UFW 防火墙..."
  apt-get install -y ufw
  ufw default deny incoming
  ufw default allow outgoing

  # 始终放行当前 SSH 端口（22 或自定义端口），避免锁死
  local current_ssh_port
  current_ssh_port="$(ss -tlnp 2>/dev/null | grep -oE ':([0-9]+)\b' | head -1 | tr -d ':')"
  if [[ -n "$current_ssh_port" ]]; then
    ufw allow "${current_ssh_port}/tcp" comment "SSH 当前端口 ${current_ssh_port}" 2>/dev/null || true
    info "已放行 SSH 当前端口 ${current_ssh_port}。"
  fi

  # 如果启用了 SSH 加固，放行加固后的端口
  if [[ "${SSH_HARDENING:-false}" == "true" ]]; then
    ufw allow "${ssh_port}/tcp" comment "SSH 加固端口 ${ssh_port}"
    info "已放行 SSH 加固端口 ${ssh_port}。"
  fi

  ufw allow 80/tcp comment 'HTTP 用于 ACME/引导'
  ufw allow 443/tcp comment 'HTTPS/Xray 入口'
  yes | ufw enable >/dev/null || true
  ufw reload >/dev/null || true
  success "UFW 防火墙配置完成。"
}
