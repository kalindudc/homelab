#!/bin/bash

sudo ufw allow 8080
sudo ufw allow 8443
sudo ufw allow 24444
sudo ufw enable
sudo ufw reload

docker network create traefik

docker-compose up -d

