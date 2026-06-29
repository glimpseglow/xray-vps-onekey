# curl | bash 安全建议

`curl | bash` 的风险在于：远程内容会直接以当前用户权限执行。如果是 root，则脚本可以修改整个系统。

更安全的方式：

```bash
curl -fsSL -o install.sh URL
less install.sh
bash install.sh --help
bash install.sh ...
```

发布正式版本时建议提供 sha256：

```bash
sha256sum xray-vps-onekey.zip > xray-vps-onekey.zip.sha256
sha256sum -c xray-vps-onekey.zip.sha256
```
