# 安装说明

## 推荐环境

- Debian 12
- root 用户
- 512MB+ 内存
- 1GB+ 可用磁盘
- 已配置 SSH 密钥登录（见 README.md 的 SSH 密钥准备章节）
- 双模式还需要：已解析到 VPS 的 Cloudflare 域名

## 直连模式（无需域名）

```bash
bash install.sh
```

## 双模式（需要域名）

```bash
bash install.sh \
  --domain ws2.example.com \
  --cf-key "你的CF_Key" \
  --cf-email "你的邮箱" \
  --ssh-port 48121 \
  --ws-path /gl2025ws
```

Cloudflare 凭据获取步骤见 [configuration.md](configuration.md#cloudflare-凭据获取指引)。

## 从直连模式无缝升级到双模式

```bash
bash install.sh --domain ws2.example.com --cf-key "你的CF_Key" --cf-email "你的邮箱"
```

UUID 和 Reality 密钥保持不变，客户端只需新增 CDN-WS 链接。

## 严格 SSH 加固

默认安全模式不会强制禁用密码登录。确认 SSH 密钥登录成功后再使用：

```bash
bash install.sh --strict-ssh
```

## 自定义参数

```bash
bash install.sh \
  --ssh-port 48121 \
  --ws-path /gl2025ws \
  --reality-dest www.microsoft.com
```
