#! /bin/bash

echo $@

sudo apt update -y
sudo apt upgrade -y

sudo apt install golang -y
sudo apt install terraform -y
sudo apt install sshpass -y
sudo apt install pipx -y

pipx ensurepath
