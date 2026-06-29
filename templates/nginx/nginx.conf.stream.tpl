# Managed by xray-vps-onekey
map $ssl_preread_server_name $xray_vps_onekey_backend {
    {{DOMAIN}}   127.0.0.1:{{NGINX_WS_PORT}};
    default     127.0.0.1:{{XRAY_REALITY_PORT}};
}

server {
    listen 443;
    ssl_preread on;
    proxy_pass $xray_vps_onekey_backend;
    proxy_connect_timeout 10s;
    proxy_timeout 300s;
}
