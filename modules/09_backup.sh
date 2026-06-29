#!/usr/bin/env bash
set -Eeuo pipefail

backup_existing_configs() {
  local snapshot_dir
  snapshot_dir="${BACKUP_DIR}/pre-install-$(date '+%Y%m%d-%H%M%S')"
  mkdir -p "$snapshot_dir"
  chmod 700 "$snapshot_dir"

  info "正在备份现有配置到 ${snapshot_dir}..."

  local paths=(
    /etc/ssh/sshd_config
    /etc/ssh/sshd_config.d
    /etc/nginx/nginx.conf
    /etc/nginx/conf.d
    /etc/nginx/sites-enabled
    /etc/nginx/sites-available
    /etc/nginx/stream-enabled
    /etc/nginx/stream.conf.d
    /etc/nginx/ssl
    /usr/local/etc/xray
    /etc/sysctl.conf
    /etc/sysctl.d
    /etc/fail2ban/jail.local
    /etc/fail2ban/jail.d
    /etc/ufw
  )

  local p
  for p in "${paths[@]}"; do
    if [[ -e "$p" ]]; then
      cp -a "$p" "$snapshot_dir/" 2>/dev/null || warn "无法备份 ${p}"
    fi
  done

  {
    echo "xray-vps-onekey 安装前快照"
    echo "创建时间: $(date '+%F %T')"
    echo "主机: $(hostname 2>/dev/null)"
    echo
    echo "===== 正在运行的服务 ====="
    systemctl list-units --type=service --state=running --no-pager 2>/dev/null || true
    echo
    echo "===== 监听端口 ====="
    ss -tulnp 2>/dev/null || true
    echo
    echo "===== UFW 状态 ====="
    ufw status verbose 2>/dev/null || echo "(ufw 未安装或未启用)"
    echo
    echo "===== sysctl BBR/IPv6 ====="
    sysctl net.ipv4.tcp_congestion_control net.ipv6.conf.all.disable_ipv6 2>/dev/null || true
    echo
    echo "===== nginx -t ====="
    nginx -t 2>&1 || true
    echo
    echo "===== xray 配置测试 ====="
    [[ -f /usr/local/etc/xray/config.json ]] && xray run -test -config /usr/local/etc/xray/config.json 2>&1 || true
  } > "${snapshot_dir}/runtime-state.txt"
  chmod 600 "${snapshot_dir}/runtime-state.txt"

  {
    tar -czf "${snapshot_dir}.tar.gz" -C "$BACKUP_DIR" "$(basename "$snapshot_dir")" 2>/dev/null \
      && rm -rf "$snapshot_dir" \
      && chmod 600 "${snapshot_dir}.tar.gz"
    success "安装前快照已保存: ${snapshot_dir}.tar.gz"
  } || {
    warn "tar 压缩失败，已保留目录形式: ${snapshot_dir}"
  }

  save_kv "$STATE_FILE" LAST_BACKUP_SNAPSHOT "${snapshot_dir}.tar.gz"
}
