#!/bin/bash
# Install vsftpd
sudo apt update
sudo apt install -y vsftpd

# Backup the original vsftpd config
sudo cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

# Set up vsftpd configuration
cat <<EOF | sudo tee /etc/vsftpd.conf
listen=NO
listen_ipv6=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000
EOF

# Set the correct ownership and permissions for the config file
sudo chown root:root /etc/vsftpd.conf
sudo chmod 644 /etc/vsftpd.conf

# Create a directory for the FTP server (adjust this to your needs)
FTP_DIR="/home/administrator"
sudo mkdir -p $FTP_DIR
sudo chown ftp:sharedgroup $FTP_DIR

sudo ufw allow 20/tcp
sudo ufw allow 21/tcp
sudo ufw allow 40000:50000/tcp
sudo ufw allow 'OpenSSH'
sudo ufw enable
sudo ufw reload

# Restart vsftpd service
sudo systemctl restart vsftpd

# Enable vsftpd to start on boot
sudo systemctl enable vsftpd

echo "FTP server setup is complete."
