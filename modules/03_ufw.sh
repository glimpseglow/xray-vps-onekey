#!/usr/bin/env bash
set -Eeuo pipefail

# 检测 SSH 实际监听的所有端口，返回空格分隔的端口号列表
# 检测顺序（多重 fallback，确保不漏）:
#   1. sshd -T（让 sshd 自己报告生效配置，处理所有 Include，最可靠）
#   2. ss -tlnp（从实际监听取，覆盖 socket activation 下的 ssh.socket）
#   3. sshd_config + sshd_config.d/*.conf（从配置文件取）
#   4. 22（最后退回）
detect_ssh_ports() {
  local ports=""

  # 1. sshd -T: 让 sshd 自己解析所有配置（包括 Include）并输出生效的 Port
  #    这是最可靠的方式，因为 sshd 自己知道它要用哪个端口
  if cmd_exists sshd; then
    local sshd_t_output
    sshd_t_output="$(sshd -T 2>/dev/null | grep -iE '^port ' | awk '{print $2}' | sort -u || true)"
    if [[ -n "$sshd_t_output" ]]; then
      ports="$sshd_t_output"
      info "通过 sshd -T 检测到 SSH 端口: ${ports}"
    fi
  fi

  # 2. ss -tlnp: 从实际网络监听取
  #    覆盖 Ubuntu socket activation 模式（ssh.socket 而非 sshd 进程）
  if [[ -z "$ports" ]]; then
    local ss_ports
    # 匹配 sshd 进程或 ssh.socket（systemd socket activation）
    ss_ports="$(ss -tlnp 2>/dev/null \
      | grep -iE 'sshd|ssh\.socket|ssh\b' \
      | grep -oE ':[0-9]+\b' \
      | tr -d ':' \
      | sort -u \
      | tr '\n' ' ' \
      | sed 's/ $//' || true)"
    if [[ -n "$ss_ports" ]]; then
      ports="$ss_ports"
      info "通过 ss -tlnp 检测到 SSH 端口: ${ports}"
    fi
  fi

  # 3. 从配置文件取（包括 sshd_config.d/*.conf）
  if [[ -z "$ports" ]]; then
    local config_ports=""
    # 主配置文件
    if [[ -f /etc/ssh/sshd_config ]]; then
      local p
      p="$(grep -iE '^\s*Port\s+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | sort -u || true)"
      [[ -n "$p" ]] && config_ports="$p"
    fi
    # 子配置目录（Ubuntu 默认 Include /etc/ssh/sshd_config.d/*.conf）
    if [[ -d /etc/ssh/sshd_config.d ]]; then
      local p2
      p2="$(grep -riE '^\s*Port\s+' /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | sort -u || true)"
      [[ -n "$p2" ]] && config_ports="${config_ports:+${config_ports} }${p2}"
    fi
    if [[ -n "$config_ports" ]]; then
      ports="$config_ports"
      info "通过配置文件检测到 SSH 端口: ${ports}"
    fi
  fi

  # 4. 最后退回 22
  if [[ -z "$ports" ]]; then
    ports="22"
    warn "无法检测 SSH 端口，使用默认 22。请确认此端口正确！"
  fi

  printf '%s' "$ports"
}

configure_ufw() {
  local ssh_port="${SSH_PORT:-$DEFAULT_SSH_PORT}"
  info "正在配置 UFW 防火墙..."
  apt-get install -y ufw
  ufw default deny incoming
  ufw default allow outgoing

  # 始终放行当前所有 SSH 端口（避免锁死）
  local ssh_ports
  ssh_ports="$(detect_ssh_ports)"

  local p
  for p in $ssh_ports; do
    ufw allow "${p}/tcp" comment "SSH 端口 ${p}" 2>/dev/null || true
  done
  info "已放行 SSH 端口: ${ssh_ports}"

  # 如果启用了 SSH 加固，放行加固后的端口
  if [[ "${SSH_HARDENING:-false}" == "true" ]]; then
    ufw allow "${ssh_port}/tcp" comment "SSH 加固端口 ${ssh_port}"
    info "已放行 SSH 加固端口 ${ssh_port}。"
  fi

  # 443 始终需要（直连模式和双模式都用）
  ufw allow 443/tcp comment 'HTTPS/Xray 入口'

  # 80 端口：双模式需要（acme 签发/续签），直连模式不需要
  if [[ -n "${DOMAIN:-}" ]]; then
    ufw allow 80/tcp comment 'HTTP 用于 ACME 证书'
  else
    info "直连模式，跳过 80 端口放行。"
  fi

  yes | ufw enable >/dev/null || true
  ufw reload >/dev/null || true
  success "UFW 防火墙配置完成。"
  info "已放行端口: ${ssh_ports// /,}/tcp（SSH）、443/tcp（Xray）${DOMAIN:+、80/tcp（ACME）}"
  info "其他所有入站端口已拒绝（deny incoming）。"
}
