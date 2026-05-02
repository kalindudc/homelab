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
    read -rp "$prompt " answer
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
    read -rsp "Enter ansible vault password: " ansible_vault_pass
    echo "pass accepted"

    temp_pass_file=$(mktemp)
    echo "$ansible_vault_pass" > "$temp_pass_file"

    # prompt to see if the user wants to generate a new gpg key
    if prompt_for_yn "Do you want to generate a new gpg key? (y/n)" "n"; then
      echo "Generating new RSA 4096 gpg key for ansible vault pass..."

      local name="${NAME:-}"
      local email="${EMAIL:-}"

      if [[ -z "$name" ]]; then
        read -rp "Enter your name: " name
      fi
      if [[ -z "$email" ]]; then
        read -rp "Enter your email: " email
      fi

      local gen_key_script
      gen_key_script=$(mktemp)
      cat > "$gen_key_script" <<EOF
%echo Generating key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $name
Name-Email: $email
Expire-Date: 0
%no-protection
%commit
%echo done
EOF
      gpg --batch --gen-key "$gen_key_script"
      rm "$gen_key_script"

      # Discover the generated key fingerprint
      gpg_key=$(gpg --list-keys --with-colons "$email" | awk -F: '/^fpr:/ {print $10; exit}')

      if [[ -z "$gpg_key" ]]; then
        echo "Failed to auto-discover the generated GPG key."
        gpg --list-keys
        read -rsp "Enter the key ID or fingerprint manually: " gpg_key
        echo
      else
        echo "Auto-discovered GPG key: $gpg_key"
      fi
    else
      gpg --list-keys
      read -rsp "Enter the key ID or fingerprint to use: " gpg_key
      echo
    fi
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
done


ALLOWED_LINUX_DISTROS=("ubuntu" "debian" "arch" "cachyos" "manjaro")

is_mac=false
if [[ "$(uname)" == "Darwin" ]]; then
  is_mac=true
fi

echo "Starting installation..."
if [[ $is_mac == true ]]; then
  echo "Installing packages for macOS..."
  "$SCRIPT_DIR"/install-mac.sh
else
  echo "Installing packages for Linux..."

  # Check for NixOS
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "$ID" == "nixos" ]]; then
      echo "Detected NixOS"
      echo "NixOS cannot be managed from this repo"
      echo "See the dependencies section in README.md"
      exit 1
    fi

    # check if the OS is in the allowed list (also check ID_LIKE for derivatives)
    is_allowed=false
    for distro in "${ALLOWED_LINUX_DISTROS[@]}"; do
      if [[ "$distro" == "$ID" ]]; then
        is_allowed=true
        break
      fi
    done
    if [[ "$is_allowed" != true && -n "${ID_LIKE:-}" && "${ID_LIKE}" =~ arch ]]; then
      is_allowed=true
      ID="arch"
    fi

    if [[ "$is_allowed" != true ]]; then
      echo "Unsupported Linux distribution: $ID"
      echo "See dependencies section in README.md and install manually."
      exit 1
    fi

    "$SCRIPT_DIR"/install.sh "$ID"
  else
    echo "No /etc/os-release file found. Cannot determine OS"
    echo "See dependencies section in README.md and install manually"
    exit 1
  fi
fi

"$SCRIPT_DIR"/install-base.sh
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
    echo "$line" >> "$HOME"/.ssh/known_hosts
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
