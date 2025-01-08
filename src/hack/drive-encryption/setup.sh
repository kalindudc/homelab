#!/bin/bash
# Sets up LUKS encryption and creates necessary backup files

get_partition_info() {
  local device="$1"

  local uuid=$(blkid -s UUID -o value "$device" 2>/dev/null)
  local label=$(blkid -s LABEL -o value "$device" 2>/dev/null)
  local type=$(blkid -s TYPE -o value "$device" 2>/dev/null)

  echo "$uuid:$label:$type"
}

validate_device() {
  local device="$1"

  # Check if device path exists
  if [ ! -b "$device" ]; then
    echo "Error: $device is not a valid block device"
    exit 1
  fi

  # Check if device is already mounted
  if mountpoint -q "$device" 2>/dev/null; then
    echo "Error: $device is already mounted"
    exit 1
  fi

  # Check if device is already a LUKS container
  if cryptsetup isLuks "$device" 2>/dev/null; then
    echo "Error: $device is already a LUKS container"
    exit 1
  fi

  # Get current partition information
  local partition_info=$(get_partition_info "$device")

  echo "Found device:"
  echo "  Device path: $device"
  echo "  Current UUID: $(echo $partition_info | cut -d: -f1)"
  echo "  Current Label: $(echo $partition_info | cut -d: -f2)"
  echo "  Current Type: $(echo $partition_info | cut -d: -f3)"

  # Confirm with user
  read -p "Is this the correct device? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
}

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 /dev/sdX /path/to/mount/point mapper_name"
  echo "Example: $0 /dev/sda1 /media encrypted_media"
  exit 1
fi

DEVICE="$1"
MOUNT_POINT="$2"
BACKUP_DIR="/root/luks_backups"
MAPPER_NAME="$3"

# Validate the device before proceeding
validate_device "$DEVICE"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

echo "WARNING: This will erase all data on $DEVICE"
read -p "Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 1
fi

apt update
apt install -y cryptsetup cryptsetup-initramfs gpg

echo "Setting up LUKS encryption..."
# Create a meaningful label based on mount point
SAFE_LABEL=$(basename "$MOUNT_POINT" | sed 's/[^a-zA-Z0-9_]/_/g')
LUKS_LABEL="${SAFE_LABEL}_luks_$(date +%Y%m%d)"

# Format the device with LUKS and set label
cryptsetup luksFormat "$DEVICE" --label "$LUKS_LABEL"
LUKS_UUID=$(cryptsetup luksUUID "$DEVICE")

# Open the LUKS container
cryptsetup luksOpen "$DEVICE" "$MAPPER_NAME"

# Create filesystem with label
mkfs.ext4 -L "${SAFE_LABEL}_fs" "/dev/mapper/$MAPPER_NAME"
FILESYSTEM_UUID=$(blkid -s UUID -o value "/dev/mapper/$MAPPER_NAME")

mkdir -p "$MOUNT_POINT"

# Generate keyfile for automatic mounting
mkdir -p /root/.luks
dd if=/dev/urandom of="/root/.luks/keyfile_${LUKS_UUID}" bs=1024 count=4
chmod 400 "/root/.luks/keyfile_${LUKS_UUID}"

# Add keyfile as additional key
cryptsetup luksAddKey "$DEVICE" "/root/.luks/keyfile_${LUKS_UUID}"

echo "Creating LUKS header backup..."
cryptsetup luksHeaderBackup "$DEVICE" \
  --header-backup-file "$BACKUP_DIR/luks_header_${LUKS_UUID}.img"

echo "Encrypting backup files..."
gpg -c "$BACKUP_DIR/luks_header_${LUKS_UUID}.img"
gpg -c "/root/.luks/keyfile_${LUKS_UUID}"

# Store all device information
cat > "$BACKUP_DIR/drive_info_${LUKS_UUID}.txt" << EOF
Original Device Path: $DEVICE
LUKS UUID: $LUKS_UUID
LUKS Label: $LUKS_LABEL
Filesystem UUID: $FILESYSTEM_UUID
Filesystem Label: ${SAFE_LABEL}_fs
Mapper name: $MAPPER_NAME
Mount point: $MOUNT_POINT
Date created: $(date)
Keyfile path: /root/.luks/keyfile_${LUKS_UUID}
EOF

gpg -c "$BACKUP_DIR/drive_info_${LUKS_UUID}.txt"

# Clean up unencrypted files
rm "$BACKUP_DIR/luks_header_${LUKS_UUID}.img"
rm "$BACKUP_DIR/drive_info_${LUKS_UUID}.txt"

# Use UUIDs in system configuration files
echo "$MAPPER_NAME UUID=$LUKS_UUID /root/.luks/keyfile_${LUKS_UUID} luks" >> /etc/crypttab

echo ""
echo "Showing output of \`id\`"
id

echo ""
echo "Find the appropriate UID and GID for the user that should have access to this drive using \`id <user>\`."
read -p "Enter a the UID of the user that should have access to this drive: " UID
read -p "Enter a the GID of the user that should have access to this drive: " GID

echo "UUID=$FILESYSTEM_UUID $MOUNT_POINT ext4 defaults,nofail,uid=$UID,git=$GID 0 2" >> /etc/fstab

# Create udev rule using LUKS UUID
cat > "/etc/udev/rules.d/99-encrypted-drive-${LUKS_UUID}.rules" << EOF
# Auto-mount rule for encrypted drive: $LUKS_LABEL
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="$LUKS_UUID", \
  RUN+="/usr/bin/systemctl start encrypted-drive-$LUKS_UUID.service"
EOF

# Create the mount script
cat > /usr/local/bin/mount-encrypted-drive-$MAPPER_NAME.sh << EOF
#!/bin/bash

# Get the kernel name and UUID from parameters
LUKS_UUID="\$1"
KERNEL_NAME="\$(basename \$(readlink -f /dev/disk/by-uuid/\$LUKS_UUID))"

# Construct device path
DEVICE="/dev/\$KERNEL_NAME"
MAPPER_NAME="$MAPPER_NAME"
MOUNT_POINT=$MOUNT_POINT
KEYFILE="/root/.luks/keyfile_\${LUKS_UUID}"

# Validate parameters
if [ ! -b "\$DEVICE" ]; then
  logger -t "mount-encrypted-drive" "Device \$DEVICE does not exist"
  echo "Device \$DEVICE does not exist"
  exit 1
fi

# Check if already mounted
if findmnt -n "\$MOUNT_POINT" > /dev/null; then
  logger -t "mount-encrypted-drive" "Drive already mounted at \$MOUNT_POINT"
  echo "Drive already mounted at \$MOUNT_POINT"
  exit 0
fi

# Open LUKS container if not already open
if [ ! -e "/dev/mapper/\$MAPPER_NAME" ]; then
  if ! cryptsetup luksOpen --key-file "\$KEYFILE" "\$DEVICE" "\$MAPPER_NAME"; then
    logger -t "mount-encrypted-drive" "Failed to open LUKS device"
    echo "Failed to open LUKS device"
    exit 1
  fi
fi

# Mount the filesystem
mount -t ext UUID="$FILESYSTEM_UUID" \$MOUNT_POINT
EOF

chmod +x /usr/local/bin/mount-encrypted-drive-$MAPPER_NAME.sh

# Create systemd service
cat > "/etc/systemd/system/encrypted-drive-${LUKS_UUID}.service" << EOF
[Unit]
Description=Mount encrypted drive ($LUKS_LABEL)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mount-encrypted-drive-$MAPPER_NAME.sh $LUKS_UUID

[Install]
WantedBy=multi-user.target
EOF

# Reload configurations
systemctl daemon-reload
udevadm control --reload-rules
systemctl enable "encrypted-drive-${LUKS_UUID}.service"

# Mount the drive
mount -a

echo
echo "Setup complete! Your encrypted drive has been configured with the following identifiers:"
echo "LUKS UUID: $LUKS_UUID"
echo "Filesystem UUID: $FILESYSTEM_UUID"
echo "LUKS Label: $LUKS_LABEL"
echo
echo "Backup files are stored in $BACKUP_DIR"
echo "Configuration files created:"
echo "- /etc/crypttab entry"
echo "- /etc/fstab entry"
echo "- /etc/udev/rules.d/99-encrypted-drive-${LUKS_UUID}.rules"
echo "- /etc/systemd/system/encrypted-drive-${LUKS_UUID}.service"
