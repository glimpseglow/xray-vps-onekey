#!/usr/bin/env bash
set -Eeuo pipefail

configure_fail2ban() {
  local ssh_port="${SSH_PORT:-$DEFAULT_SSH_PORT}"
  info "正在安装和配置 Fail2ban..."
  apt-get install -y fail2ban
  mkdir -p /etc/fail2ban/jail.d

  # 检查是否有旧的 jail.local 覆盖我们的配置
  if [[ -f /etc/fail2ban/jail.local ]] && ! grep -q "xray-vps-onekey" /etc/fail2ban/jail.local 2>/dev/null; then
    warn "检测到 /etc/fail2ban/jail.local 已存在且非本项目管理，可能会覆盖配置。"
    warn "已备份到 ${BACKUP_DIR}/"
    backup_file /etc/fail2ban/jail.local
  fi

  # 写入我们的 jail 配置
  write_file /etc/fail2ban/jail.d/xray-vps-onekey-sshd.local \
    "$(render_template "${TEMPLATE_DIR}/fail2ban/sshd.local.tpl" "SSH_PORT=${ssh_port}")"

  # 确保没有旧的 logpath 配置残留
  # Debian/Ubuntu 默认的 defaults-debian.conf 可能启用 sshd jail 但用 auth.log
  # 我们用自己的配置覆盖，但如果有 jail.local 里的 [sshd] 段会覆盖 jail.d/
  # 所以也写一份 jail.local 确保 [sshd] 用 systemd backend
  local jail_local="/etc/fail2ban/jail.local"
  if [[ ! -f "$jail_local" ]] || ! grep -q "xray-vps-onekey" "$jail_local" 2>/dev/null; then
    backup_file "$jail_local"
    cat > "$jail_local" <<EOF
# Managed by xray-vps-onekey
[DEFAULT]
backend = systemd

$(cat "${TEMPLATE_DIR}/fail2ban/sshd.local.tpl" | sed "s/{{SSH_PORT}}/${ssh_port}/")
EOF
    info "已写入 /etc/fail2ban/jail.local（systemd backend）。"
  fi

  # 重启前先清理 failed 状态
  systemctl enable fail2ban >/dev/null
  systemctl reset-failed fail2ban 2>/dev/null || true
  systemctl stop fail2ban 2>/dev/null || true
  sleep 1
  systemctl start fail2ban 2>/dev/null || true

  # 验证
  sleep 2
  if systemctl is-active --quiet fail2ban; then
    success "Fail2ban 配置完成，服务运行中。"
  else
    warn "Fail2ban 服务启动失败，不影响 Xray 正常使用。"
    warn "--- systemctl status fail2ban ---"
    systemctl --no-pager --full status fail2ban 2>&1 | tail -15 || true
    warn "--- 当前 jail 配置 ---"
    grep -rn "backend\|logpath\|\[sshd\]" /etc/fail2ban/jail.local /etc/fail2ban/jail.d/ 2>/dev/null || true
    warn "可手动排查: journalctl -u fail2ban -e --no-pager"
  fi
}
