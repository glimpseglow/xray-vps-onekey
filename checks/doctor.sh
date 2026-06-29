#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../modules/00_common.sh
source "${SCRIPT_DIR}/modules/00_common.sh"
load_state

check_service() {
  local svc="$1"
  if systemctl is-active --quiet "$svc"; then
    success "${svc} 运行中"
  else
    warn "${svc} 未运行"
    systemctl --no-pager --full status "$svc" || true
  fi
}

doctor_main() {
  info "正在执行安装后健康检查..."
  check_service ssh
  check_service nginx
  check_service xray
  check_service fail2ban

  if cmd_exists ufw; then
    ufw status verbose || true
  fi

  echo
  if [[ -n "${DOMAIN:-}" ]]; then
    info "监听端口（双模式）:"
    ss -tulnp | grep -E ':443|:8080|:10443|:20443' || warn "未找到预期端口。"
  else
    info "监听端口（直连模式）:"
    ss -tulnp | grep -E ':443' || warn "未找到 443 端口。"
  fi

  echo
  info "BBR 状态:"
  sysctl net.ipv4.tcp_congestion_control || true

  echo
  info "IPv6 状态:"
  sysctl net.ipv6.conf.all.disable_ipv6 || true

  echo
  if [[ -n "${DOMAIN:-}" ]]; then
    info "Nginx 配置测试:"
    nginx -t
  else
    info "Nginx 配置测试（直连模式，不需要 nginx）:"
    cmd_exists nginx && nginx -t || info "未安装 nginx，跳过。"
  fi

  echo
  info "Xray 配置测试:"
  xray run -test -config /usr/local/etc/xray/config.json

  success "健康检查完成。"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  doctor_main "$@"
fi
