#!/bin/bash

# Exit script on any error
set -e

# Update and install Docker
echo "Updating system and installing Docker..."
sudo apt-get update -y
sudo apt-get install -y docker.io

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Install Docker Compose
echo "Installing Docker Compose..."
sudo apt install -y docker-compose

DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.12.2/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose

sudo chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

sudo usermod -aG docker $USER

echo "Docker setup complete, rebooting in 5 seconds..."
sleep 5
sudo reboot
