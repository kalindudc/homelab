#!/bin/bash
JELLYFINDIR="/usr/share/jellyfin"
FFMPEGDIR="/usr/lib/jellyfin-ffmpeg"

/jellyfin/jellyfin \
 -d $JELLYFINDIR/data \
 -C $JELLYFINDIR/cache \
 -c $JELLYFINDIR/config \
 -l $JELLYFINDIR/log \
 --ffmpeg $FFMPEGDIR/ffmpeg
