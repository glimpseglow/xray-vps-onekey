# Managed by xray-vps-onekey
server {
    listen 127.0.0.1:{{NGINX_WS_PORT}} ssl http2;
    server_name {{DOMAIN}};

    ssl_certificate /etc/nginx/ssl/{{CERT_DOMAIN}}/fullchain.cer;
    ssl_certificate_key /etc/nginx/ssl/{{CERT_DOMAIN}}/private.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location {{WS_PATH}} {
        if ($http_upgrade != "websocket") {
            return 404;
        }

        proxy_redirect off;
        proxy_pass http://127.0.0.1:{{XRAY_WS_PORT}};
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
    }

    location / {
        return 404;
    }
}