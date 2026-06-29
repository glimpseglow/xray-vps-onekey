# Managed by xray-vps-onekey
[sshd]
enabled = true
backend = systemd
port = {{SSH_PORT}}
filter = sshd
maxretry = 5
bantime = 1h
findtime = 10m
