#! /bin/bash

set -e

DISTRO="${1:-}"

install_with_pacman() {
  echo "Installing packages with pacman..."
  sudo pacman -Syu --noconfirm
  sudo pacman -S --noconfirm go terraform python-pipx base-devel git
}

install_aur_package() {
  local pkg="$1"
  if command -v yay &> /dev/null; then
    yay -S --noconfirm "$pkg"
  elif command -v paru &> /dev/null; then
    paru -S --noconfirm "$pkg"
  else
    echo "No AUR helper found (yay/paru). Installing $pkg manually..."
    local tmpdir
    tmpdir=$(mktemp -d)
    git clone "https://aur.archlinux.org/${pkg}.git" "$tmpdir/$pkg"
    cd "$tmpdir/$pkg"
    makepkg -si --noconfirm
    cd -
    rm -rf "$tmpdir"
  fi
}

if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  . /etc/os-release
fi

# Determine package manager from distro or ID_LIKE
is_arch_like=false
if [[ "$DISTRO" == "arch" || "$DISTRO" == "cachyos" || "$DISTRO" == "manjaro" ]]; then
  is_arch_like=true
elif [[ -n "${ID_LIKE:-}" && "${ID_LIKE}" =~ arch ]]; then
  is_arch_like=true
fi

if [[ "$is_arch_like" == true ]]; then
  install_with_pacman

  # sshpass is in AUR on Arch-based distros
  if ! command -v sshpass &> /dev/null; then
    install_aur_package "sshpass"
  fi
else
  # Default to apt (Debian/Ubuntu)
  echo "Installing packages with apt..."
  sudo apt update -y
  sudo apt upgrade -y

  sudo apt install golang -y
  sudo apt install terraform -y
  sudo apt install sshpass -y
  sudo apt install pipx -y
fi

pipx ensurepath
