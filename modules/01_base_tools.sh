#!/usr/bin/env bash
set -Eeuo pipefail

install_base_tools() {
  info "正在安装基础工具..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y \
    ca-certificates curl wget git jq unzip zip tar openssl socat cron \
    sudo vim htop net-tools dnsutils lsb-release gnupg python3 iproute2
  success "基础工具安装完成。"
}
