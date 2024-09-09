#!/bin/bash

sudo apt update
sudo apt install -y openjdk-21-jre-headless
sudo su -c "wget -qO- https://script.mcsmanager.com/setup_cn.sh | bash"

sudo ufw allow 23335/tcp
sudo ufw allow 23333/tcp
sudo ufw allow 24444/tcp
sudo ufw allow 35566/tcp
sudo ufw enable
sudo ufw reload
