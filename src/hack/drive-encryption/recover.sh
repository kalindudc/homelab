#!/bin/bash
# Recovers a LUKS-encrypted drive using backup files and UUID identification

get_device_path() {
  local uuid="$1"
  local path=""

  # Try different methods to find the device
  if [ -e "/dev/disk/by-uuid/$uuid" ]; then
    path=$(readlink -f "/dev/disk/by-uuid/$uuid")
  else
    path=$(blkid -U "$uuid" 2>/dev/null)
  fi

  if [ -n "$path" ] && [ -b "$path" ]; then
    echo "$path"
    return 0
  fi
  return 1
}

validate_backup_files() {
  local backup_dir="$1"
  local luks_uuid="$2"

  local required_files=(
    "luks_header_${luks_uuid}.img.gpg"
    "drive_info_${luks_uuid}.txt.gpg"
  )

  for file in "${required_files[@]}"; do
    if [ ! -f "$backup_dir/$file" ]; then
      echo "Error: Required backup file $file not found in $backup_dir"
      return 1
    fi
  done
  return 0
}

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Validate command line arguments
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 /dev/sdX /path/to/backup/directory /path/to/mount/point"
  echo "Example: $0 /dev/sdb /root/luks_backups /media"
  exit 1
fi

DEVICE="$1"
BACKUP_DIR="$2"
MOUNT_POINT="$3"

# Validate input device
if [ ! -b "$DEVICE" ]; then
  echo "Error: Device $DEVICE is not a valid block device"
  exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
  echo "Error: Backup directory $BACKUP_DIR does not exist"
  exit 1
fi

# Create temporary working directory
TEMP_DIR=$(mktemp -d)
chmod 700 "$TEMP_DIR"

# List available backups
echo "Available LUKS backups in $BACKUP_DIR:"
for info_file in "$BACKUP_DIR"/drive_info_*.txt.gpg; do
  if [ -f "$info_file" ]; then
    uuid=$(basename "$info_file" | sed 's/drive_info_\(.*\)\.txt\.gpg/\1/')
    echo "LUKS UUID: $uuid"
    gpg -q -d "$info_file" 2>/dev/null | grep -E "LUKS Label:|Mount point:|Original Device Path:"
    echo "---"
  fi
done

# Ask for LUKS UUID selection
read -p "Enter the LUKS UUID you want to recover: " LUKS_UUID

# Validate backup files exist for selected UUID
if ! validate_backup_files "$BACKUP_DIR" "$LUKS_UUID"; then
  echo "Error: Missing backup files for UUID $LUKS_UUID"
  rm -rf "$TEMP_DIR"
  exit 1
fi

echo "Decrypting backup files..."
# Decrypt drive info file first to get configuration details
gpg -d "$BACKUP_DIR/drive_info_${LUKS_UUID}.txt.gpg" > "$TEMP_DIR/drive_info.txt"

# Extract important information from drive info
MAPPER_NAME=$(grep "Mapper name:" "$TEMP_DIR/drive_info.txt" | cut -d: -f2 | tr -d ' ')
FILESYSTEM_UUID=$(grep "Filesystem UUID:" "$TEMP_DIR/drive_info.txt" | cut -d: -f2 | tr -d ' ')
FILESYSTEM_LABEL=$(grep "Filesystem Label:" "$TEMP_DIR/drive_info.txt" | cut -d: -f2 | tr -d ' ')

# Decrypt LUKS header backup
echo "Restoring LUKS header..."
gpg -d "$BACKUP_DIR/luks_header_${LUKS_UUID}.img.gpg" > "$TEMP_DIR/luks_header.img"

# Restore LUKS header
if ! cryptsetup luksHeaderRestore "$DEVICE" --header-backup-file "$TEMP_DIR/luks_header.img"; then
  echo "Error: Failed to restore LUKS header"
  rm -rf "$TEMP_DIR"
  exit 1
fi

# Set up keyfile
mkdir -p /root/.luks
if [ -f "$BACKUP_DIR/keyfile_${LUKS_UUID}.gpg" ]; then
  echo "Restoring keyfile..."
  gpg -d "$BACKUP_DIR/keyfile_${LUKS_UUID}.gpg" > "/root/.luks/keyfile_${LUKS_UUID}"
  chmod 400 "/root/.luks/keyfile_${LUKS_UUID}"
else
  echo "Warning: Keyfile backup not found. You may need to add a new key manually."
  exit 1
fi

# Create mount point
mkdir -p "$MOUNT_POINT"

# Update system configuration files
echo "Updating system configuration..."

# Update crypttab
if ! grep -q "UUID=$LUKS_UUID" /etc/crypttab; then
  echo "$MAPPER_NAME UUID=$LUKS_UUID /root/.luks/keyfile_${LUKS_UUID} luks" >> /etc/crypttab
fi

# Update fstab
if ! grep -q "UUID=$FILESYSTEM_UUID" /etc/fstab; then
  echo ""
  echo "Showing output of \`id\`"
  id

  echo ""
  echo "Find the appropriate UID and GID for the user that should have access to this drive using \`id <user>\`."
  read -p "Enter a the UID of the user that should have access to this drive: " UID
  read -p "Enter a the GID of the user that should have access to this drive: " GID

  echo "UUID=$FILESYSTEM_UUID $MOUNT_POINT ext4 defaults,nofail,uid=$UID,git=$GID 0 2" >> /etc/fstab
fi

# Create udev rule
cat > "/etc/udev/rules.d/99-encrypted-drive-${LUKS_UUID}.rules" << EOF
# Auto-mount rule for encrypted drive with UUID: $LUKS_UUID
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="$LUKS_UUID", \
  RUN+="/usr/local/bin/mount-encrypted-drive.sh %k $LUKS_UUID"
EOF

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

# Reload system configurations
systemctl daemon-reload
udevadm control --reload-rules
systemctl enable "encrypted-drive-${LUKS_UUID}.service"

# Open and mount the drive
echo "Mounting the drive..."
cryptsetup luksOpen "$DEVICE" "$MAPPER_NAME"
mount -a

# Clean up
rm -rf "$TEMP_DIR"

echo
echo "Recovery complete! Your encrypted drive has been restored:"
echo "LUKS UUID: $LUKS_UUID"
echo "Filesystem UUID: $FILESYSTEM_UUID"
echo "Mount point: $MOUNT_POINT"
echo
echo "The drive has been configured for automatic mounting"
echo "You can verify the mount with: df -h $MOUNT_POINT"
