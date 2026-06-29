#!/usr/bin/env bash
set -Eeuo pipefail

install_xray() {
  info "正在通过官方脚本安装 Xray..."
  if ! cmd_exists xray; then
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  else
    info "Xray 已安装: $(xray version | head -n1 || true)"
  fi

  # Xray 官方 unit 默认以 User=nobody 运行，无法读取
  # config.json（权限 600，root:root）和 /usr/local/lib/xray/ 下的 geoip 文件。
  # 注释掉 User= 行，改为以 root 运行。
  local xray_unit="/etc/systemd/system/xray.service"
  if [[ -f "$xray_unit" ]] && grep -qE '^[[:space:]]*User[[:space:]]*=' "$xray_unit"; then
    backup_file "$xray_unit"
    sed -i.bak -E 's/^([[:space:]]*User[[:space:]]*=).*/#\1nobody  # commented out by xray-vps-onekey (config is chmod 600 root:root)/' "$xray_unit"
    rm -f "${xray_unit}.bak"
    systemctl daemon-reload
    info "已注释掉 xray.service 中的 User=nobody（config.json 为 root:root 600）。"
  fi

  systemctl daemon-reload
  systemctl enable xray >/dev/null || true
  success "Xray 安装完成。"
}

generate_xray_secrets() {
  load_state
  info "正在生成或加载 Xray 密钥..."
  if [[ -z "${XRAY_UUID:-}" ]]; then
    XRAY_UUID="$(xray uuid)"
    save_kv "$SECRETS_FILE" XRAY_UUID "$XRAY_UUID"
  fi

  if [[ -z "${REALITY_PRIVATE_KEY:-}" || -z "${REALITY_PUBLIC_KEY:-}" ]]; then
    local key_output private_key public_key
    key_output="$(xray x25519)"
    private_key="$(printf '%s\n' "$key_output" | awk -F': ' '/Private key|PrivateKey|Password/ {print $2; exit}')"
    public_key="$(printf '%s\n' "$key_output" | awk -F': ' '/Public key|PublicKey/ {print $2; exit}')"
    [[ -n "$private_key" && -n "$public_key" ]] || fail "解析 xray x25519 输出失败。"
    REALITY_PRIVATE_KEY="$private_key"
    REALITY_PUBLIC_KEY="$public_key"
    save_kv "$SECRETS_FILE" REALITY_PRIVATE_KEY "$REALITY_PRIVATE_KEY"
    save_kv "$SECRETS_FILE" REALITY_PUBLIC_KEY "$REALITY_PUBLIC_KEY"
  fi

  if [[ -z "${REALITY_SHORT_ID:-}" ]]; then
    REALITY_SHORT_ID="$(openssl rand -hex 8)"
    save_kv "$SECRETS_FILE" REALITY_SHORT_ID "$REALITY_SHORT_ID"
  fi
  chmod 600 "$SECRETS_FILE"
  success "Xray 密钥已就绪。"
}

render_xray_config() {
  load_state
  local ws_path="${WS_PATH:-$DEFAULT_WS_PATH}"
  local reality_dest="${REALITY_DEST:-$DEFAULT_REALITY_DEST}"
  local server_names="${REALITY_SERVER_NAMES:-$DEFAULT_REALITY_SERVER_NAMES}"
  local config_path="/usr/local/etc/xray/config.json"
  local tpl mode

  if [[ -n "${DOMAIN:-}" ]]; then
    mode="dual"
    tpl="${TEMPLATE_DIR}/xray/config-dual.json.tpl"
    local reality_port="${XRAY_REALITY_PORT:-$DEFAULT_REALITY_PORT}"
    local ws_port="${XRAY_WS_PORT:-$DEFAULT_WS_PORT}"
    info "正在渲染双模式 Xray 配置（Reality + WS）: ${config_path}..."
    write_file_600 "$config_path" \
      "$(render_template "$tpl" \
         "XRAY_REALITY_PORT=${reality_port}" "XRAY_WS_PORT=${ws_port}" \
         "XRAY_UUID=${XRAY_UUID}" "REALITY_DEST=${reality_dest}" \
         "REALITY_SERVER_NAMES=${server_names}" "REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}" \
         "REALITY_SHORT_ID=${REALITY_SHORT_ID}" "WS_PATH=${ws_path}")"
  else
    mode="direct"
    tpl="${TEMPLATE_DIR}/xray/config-direct.json.tpl"
    info "正在渲染直连模式 Xray 配置（仅 Reality）: ${config_path}..."
    write_file_600 "$config_path" \
      "$(render_template "$tpl" \
         "XRAY_UUID=${XRAY_UUID}" "REALITY_DEST=${reality_dest}" \
         "REALITY_SERVER_NAMES=${server_names}" "REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}" \
         "REALITY_SHORT_ID=${REALITY_SHORT_ID}")"
  fi

  save_kv "$STATE_FILE" XRAY_MODE "$mode"

  xray run -test -config "$config_path"

  # 直连模式下，如果 nginx 还在占用 443，xray 会启动失败
  if [[ "$mode" == "direct" ]] && systemctl is-active --quiet nginx 2>/dev/null; then
    warn "检测到 nginx 正在运行并可能占用 443 端口，直连模式不需要 nginx。"
    warn "正在停止 nginx 以释放 443 端口..."
    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
  fi

  systemctl daemon-reload
  systemctl enable --now xray
  systemctl restart xray 2>/dev/null || true

  # 验证 xray 是否真的启动成功
  sleep 2
  if ! systemctl is-active --quiet xray; then
    warn "Xray 服务启动失败！"
    warn "--- systemctl status xray ---"
    systemctl --no-pager --full status xray 2>&1 || true
    warn "--- journalctl 最近 20 行 ---"
    journalctl -u xray -n 20 --no-pager 2>&1 || true
    warn "--- xray.service User= 行 ---"
    grep -nE '^\s*User\s*=' /etc/systemd/system/xray.service 2>/dev/null || echo "(未找到 User= 行)"
    warn "--- 443 端口占用 ---"
    ss -tulnp | grep ':443' || echo "(443 未被监听)"
    fail "Xray 启动失败，请根据上面的日志排查。常见原因: 1) xray.service 的 User=nobody 未注释  2) 443 端口被占用  3) 配置文件权限问题"
  fi

  # 验证端口是否在监听
  local expected_port
  if [[ "$mode" == "direct" ]]; then
    expected_port="443"
  else
    expected_port="${XRAY_REALITY_PORT:-$DEFAULT_REALITY_PORT}"
  fi

  if ! port_in_use "$expected_port"; then
    warn "Xray 服务运行中，但端口 ${expected_port} 未在监听。"
    ss -tulnp | grep -E ":${expected_port}" || true
    fail "请检查 Xray 配置和日志。"
  fi

  success "Xray 配置已生效（模式: ${mode}，监听端口: ${expected_port}）。"
}
