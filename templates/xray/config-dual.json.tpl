{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "reality-in",
      "listen": "127.0.0.1",
      "port": {{XRAY_REALITY_PORT}},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "{{XRAY_UUID}}", "flow": "xtls-rprx-vision" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "{{REALITY_DEST}}:443",
          "serverNames": {{REALITY_SERVER_NAMES}},
          "privateKey": "{{REALITY_PRIVATE_KEY}}",
          "shortIds": ["{{REALITY_SHORT_ID}}"]
        }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true }
    },
    {
      "tag": "ws-in",
      "listen": "127.0.0.1",
      "port": {{XRAY_WS_PORT}},
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "{{XRAY_UUID}}", "flow": "" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "{{WS_PATH}}" }
      },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" },
      { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" }
    ]
  }
}
