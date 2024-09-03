#!/bin/bash
# Install nginx
sudo apt update
sudo apt install -y nginx

# Create the directory to serve files from (adjust this to your needs)
WEB_DIR="/home/administrator/file_server"
sudo mkdir -p $WEB_DIR
sudo chown -R administrator:www-data $WEB_DIR
sudo chmod -R 751 /home/administrator
sudo chmod -R 2755 $WEB_DIR

# Set up nginx configuration
cat <<EOF | sudo tee /etc/nginx/sites-available/file_server
server {
    listen 8080 default_server;
    listen [::]:8080 default_server;

    root $WEB_DIR;
    server_name _;

    location / {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }
}
EOF

# Set up nginx service
cat <<EOF | sudo tee /lib/systemd/system/nginx.service
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx.pid
TimeoutStopSec=5
KillMode=mixed
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable the configuration
sudo ln -s /etc/nginx/sites-available/file_server /etc/nginx/sites-enabled/

# Test the nginx configuration
sudo nginx -t

sudo ufw allow 'Nginx HTTP'
sudo ufw allow 'Nginx HTTPS'
sudo ufw allow 8080/tcp
sudo ufw enable
sudo ufw reload

# Restart daemon and nginx service
sudo systemctl daemon-reload
sudo systemctl restart nginx

# Enable nginx to start on boot
sudo systemctl enable nginx

echo "Web-based file server setup is complete."
