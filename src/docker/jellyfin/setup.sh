#!/bin/bash

# create user jellyfin and group jellyfin with PUID 109 and PGID 112
groupadd -g 112 jellyfin
useradd -u 109 -g 112 jellyfin

JELLYFINDIR="/usr/share/jellyfin"

# Create directories
mkdir -p $JELLYFINDIR/data
mkdir -p $JELLYFINDIR/cache
mkdir -p $JELLYFINDIR/config
mkdir -p $JELLYFINDIR/log

# Set permissions
sudo chown -R jellyfin:jellyfin $JELLYFINDIR
