#!/usr/bin/env bash
set -Eeuo pipefail

configure_ssh_hardening() {
  local ssh_port="${SSH_PORT:-$DEFAULT_SSH_PORT}"
  local strict="${STRICT_SSH:-false}"
  info "正在配置 SSH 加固，端口 ${ssh_port}..."
  mkdir -p /etc/ssh/sshd_config.d
  local file="/etc/ssh/sshd_config.d/99-xray-vps-onekey.conf"
  backup_file "$file"

  # 安装前检查：如果 root 没有 authorized_keys，大声警告
  if [[ ! -s /root/.ssh/authorized_keys ]]; then
    warn "/root/.ssh/authorized_keys 为空或不存在。"
    warn "安装后 root 只能通过 SSH 密钥登录（PermitRootLogin=prohibit-password）。"
    warn "如果你现在是用密码登录的，安装完成后将被锁死。"
    warn "请先在另一个终端配置好 SSH 密钥登录再继续："
    warn "  ssh-copy-id root@\$(curl -4fsS https://api.ipify.org)"
    warn "然后验证：ssh root@<本机IP>  （应该不再要求密码）"
    if [[ "$strict" == "true" ]]; then
      fail "STRICT_SSH=true 但 /root/.ssh/authorized_keys 不存在，拒绝继续。"
    fi
    warn "当前为安全模式（非 root 用户仍可用密码登录）。"
    warn "10 秒内可按 Ctrl+C 中止并先配置 SSH 密钥..."
    sleep 10
  fi

  local tpl
  if [[ "$strict" == "true" ]]; then
    tpl="${TEMPLATE_DIR}/ssh/sshd_config.d.tpl"
  else
    tpl="${TEMPLATE_DIR}/ssh/sshd_config.d.safe.tpl"
    warn "安全模式：未强制禁用密码登录。确认密钥登录正常后可用 --strict-ssh 重新运行。"
  fi

  write_file "$file" "$(render_template "$tpl" "SSH_PORT=${ssh_port}")"
  sshd -t
  systemctl reload ssh || systemctl restart ssh
  success "SSH 加固配置已生效。"
  echo
  warn "=========================================================="
  warn "  SSH 端口已改为 ${ssh_port}。"
  warn "  root 登录方式已改为仅密钥（PermitRootLogin=prohibit-password）。"
  warn "  请先不要关闭当前终端！"
  warn "  请另开一个终端验证能否用新端口登录："
  warn "    ssh -p ${ssh_port} root@<你的服务器IP>"
  warn "  验证成功后，再关闭当前终端。"
  warn "  如果被锁死，通过 VPS 网页控制台恢复："
  warn "    rm /etc/ssh/sshd_config.d/99-xray-vps-onekey.conf && systemctl restart ssh"
  warn "=========================================================="
  echo
}
