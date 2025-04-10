#! /usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_DIR="$SCRIPT_DIR/.."

usage() {
  echo "Usage: $0 [--setup-ansible-vault] [-h|--help]"
  echo "Options:"
  echo "  --setup-ansible-vault   Setup ansible vault pass"
  echo "  -h, --help              Show this help message"
  exit 1
}

prompt_for_yn() {
  local prompt="$1"
  local default="$2"
  local answer

  while true; do
    read -p "$prompt " answer
    answer=${answer:-$default}

    case "$answer" in
      [Yy]* ) return 0;;
      [Nn]* ) return 1;;
      * ) echo "Please answer y or N.";;
    esac
  done
}

setup_ansible_vault() {
  # setup ansible vault pass
  ANSIBLE_VAULT_PASS_FILE="$HOME/.ansible_vault_pass.gpg"
  if [[ ! -f $ANSIBLE_VAULT_PASS_FILE ]]; then
    echo "Creating ansible vault pass file..."
    read -sp "Enter ansible vault password: " ansible_vault_pass
    echo "pass accepted"

    temp_pass_file=$(mktemp)
    echo "$ansible_vault_pass" > "$temp_pass_file"

    # prompt to see if the user wants to generate a new gpg key
    if prompt_for_yn "Do you want to generate a new gpg key? (y/n)" "n"; then
      echo "Generating new gpg key for ansible vault pass..."
      gpg --full-generate-key
    fi
    gpg --list-keys

    read -sp "Enter the key for the new gpg key: " gpg_key
    gpg --encrypt --recipient "$gpg_key" --output "$ANSIBLE_VAULT_PASS_FILE" "$temp_pass_file"
    rm "$temp_pass_file"
    echo "Ansible vault pass file created."
  else
    echo "Ansible vault pass file already exists."
    echo "If the password has changed, please delete the file and run this script again."
  fi
}

# Parse options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --setup-ansible-vault)
      setup_ansible_vault
      exit 0
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
  shift
done


ALLOWED_LINUX_DISTROS=("ubuntu" "debian")

is_mac=false
if [[ "$(uname)" == "Darwin" ]]; then
  is_mac=true
fi

echo "Starting installation..."
if [[ $is_mac == true ]]; then
  echo "Installing packages for macOS..."
  $SCRIPT_DIR/install-mac.sh
else
  echo "Installing packages for Linux..."

  # Check for NixOS
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" == "nixos" ]]; then
      echo "Detected NixOS"
      echo "NixOS cannot be managed from this repo"
      echo "See the dependencies section in README.md"
      exit 1
    fi

    # check if the OS is in the allowed list
    if [[ ! " ${ALLOWED_LINUX_DISTROS[@]} " =~ " ${ID} " ]]; then
      echo "Unsupported Linux distribution: $ID"
      echo "See dependencies section in README.md and install manually."
      exit 1
    fi

    $SCRIPT_DIR/install.sh $ID
  else
    echo "No /etc/os-release file found. Cannot determine OS"
    echo "See dependencies section in README.md and install manually"
    exit 1
  fi
fi

$SCRIPT_DIR/install-base.sh
echo "Package installation complete."
echo " "

# Add new hosts to known_hosts
echo "Adding new hosts to known_hosts..."
temp_hosts=$(mktemp)
cat "$HOMELAB_DIR/src/known_hosts.txt" | xargs -I {} ssh-keyscan {} > "$temp_hosts"

# Add missing entries
while IFS= read -r line; do
  host=$(echo "$line" | cut -d' ' -f1)
  if ! ssh-keygen -F "$host" > /dev/null; then
    echo "$line" >> $HOME/.ssh/known_hosts
    echo "Added $host"
  fi
done < "$temp_hosts"

rm "$temp_hosts"

echo "known_hosts updated."
echo " "

setup_ansible_vault
echo "Ansible vault pass setup complete."
echo " "

echo "Homelab initialization complete."
echo "Test with 'ansible-playbook -i src/ansible/inventory/servers.ini src/ansible/playbooks/ping_playbook.yml'"
