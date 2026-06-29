#!/usr/bin/env bash
set -Eeuo pipefail

configure_sysctl_bbr_ipv6() {
  info "正在配置 BBR 并关闭 IPv6..."
  local file="/etc/sysctl.d/99-xray-vps-onekey.conf"
  backup_file "$file"
  cat > "$file" <<'CONF'
# Managed by xray-vps-onekey
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_syncookies = 1
fs.file-max = 1048576
CONF
  sysctl --system >/dev/null
  success "BBR 和 IPv6 sysctl 配置已生效。"
}
