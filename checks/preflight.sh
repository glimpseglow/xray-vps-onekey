#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../modules/00_common.sh
source "${SCRIPT_DIR}/modules/00_common.sh"

preflight_main() {
  require_root
  info "正在执行安装前检查..."

  if [[ ! -f /etc/os-release ]]; then
    fail "无法检测操作系统。"
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "12" ]]; then
    fail "本安装器目前仅支持 Debian 12。检测到: ${PRETTY_NAME:-unknown}。"
  fi
  success "系统检查通过: ${PRETTY_NAME:-Debian 12}"

  if ! pidof systemd >/dev/null 2>&1; then
    fail "需要 systemd。"
  fi
  success "已检测到 systemd"

  if ! cmd_exists apt-get; then
    fail "需要 apt-get。"
  fi

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|aarch64|arm64) success "架构支持: ${arch}" ;;
    *) fail "不支持的架构: ${arch}" ;;
  esac

  local mem_kb disk_kb
  mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  if [[ "$mem_kb" -lt 262144 ]]; then
    fail "内存低于 256MB。"
  elif [[ "$mem_kb" -lt 524288 ]]; then
    warn "内存低于 512MB。可能可以运行，但建议 512MB 以上。"
  else
    success "内存检查通过"
  fi

  disk_kb="$(df -Pk / | awk 'NR==2 {print $4}')"
  if [[ "$disk_kb" -lt 1048576 ]]; then
    fail "根分区可用空间低于 1GB。"
  fi
  success "磁盘空间检查通过"

  local required_ports=(80 443 8080 10443 20443)
  local p
  for p in "${required_ports[@]}"; do
    if port_in_use "$p"; then
      warn "端口 ${p} 已被占用。安装器可能会复用或替换相关 nginx/xray 配置，但未知进程可能导致失败。"
      ss -tulnp | grep -E ":${p}\b" || true
    fi
  done

  local conflicts=(apache2 caddy v2ray xray nginx)
  local svc
  for svc in "${conflicts[@]}"; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
      warn "检测到已有服务: ${svc}。安装器是幂等的，但建议检查现有自定义配置。"
    fi
  done

  if ! getent hosts github.com >/dev/null 2>&1; then
    warn "当前无法解析 github.com。安装 Xray/acme.sh 可能失败。"
  else
    success "DNS 解析正常"
  fi

  local ipv4
  ipv4="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1); exit}')"
  if [[ -z "$ipv4" ]]; then
    warn "无法检测主 IPv4 地址。"
  else
    success "检测到主 IPv4 地址: ${ipv4}"
  fi

  info "安装前检查完成。"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  preflight_main "$@"
fi
