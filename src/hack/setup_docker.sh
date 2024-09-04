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
sudo apt-get install -y docker-compose
