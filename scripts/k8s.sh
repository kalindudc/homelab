#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTION]

Kubernetes cluster lifecycle management for the homelab k3s cluster.

Options:
  -i, --init        Install kubectl and helm on the workstation
  -d, --deploy      Deploy the k3s cluster using Ansible
  -u, --upgrade     Upgrade the k3s cluster using Ansible
  -k, --kubeconfig  Fetch and configure local kubeconfig
  -h, --help        Show this help message
EOF
}

init() {
  if command -v kubectl &>/dev/null && command -v helm &>/dev/null; then
    echo "kubectl and helm are already installed."
    exit 0
  fi

  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Installing kubectl and helm with brew..."
    brew install kubectl helm
    exit 0
  fi

  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
  fi

  case "${ID:-}" in
    arch | cachyos | manjaro)
      echo "Installing kubectl and helm with pacman..."
      sudo pacman -S --noconfirm kubectl helm
      ;;
    ubuntu | debian)
      echo "Installing kubectl and helm with apt..."
      sudo apt-get update
      sudo apt-get install -y kubectl helm
      ;;
    *)
      echo "Unsupported OS: ${ID:-unknown}. Please install kubectl and helm manually."
      exit 1
      ;;
  esac
}

deploy() {
  echo "Installing Ansible collection requirements..."
  ansible-galaxy collection install -r "${PROJECT_DIR}/src/ansible/requirements.yml" --force

  echo "Deploying k3s cluster..."
  ansible-playbook -i "${PROJECT_DIR}/src/ansible/inventory/k3s.ini" --extra-vars "@${PROJECT_DIR}/src/ansible/playbooks/vault.yml" "${PROJECT_DIR}/src/ansible/playbooks/k3s_deploy.yml"
}

upgrade() {
  echo "Upgrading k3s cluster..."
  ansible-playbook -i "${PROJECT_DIR}/src/ansible/inventory/k3s.ini" --extra-vars "@${PROJECT_DIR}/src/ansible/playbooks/vault.yml" "${PROJECT_DIR}/src/ansible/playbooks/k3s_upgrade.yml"
}

kubeconfig() {
  local cluster_context
  cluster_context=$(grep "^cluster_context:" "${PROJECT_DIR}/src/ansible/inventory/group_vars/k3s_cluster.yml" 2>/dev/null | sed 's/cluster_context: *//;s/["'"'"']//g' | tr -d ' ')
  cluster_context=${cluster_context:-default}

  echo "Fetching kubeconfig from server..."
  mkdir -p ~/.kube
  ansible -i "${PROJECT_DIR}/src/ansible/inventory/k3s.ini" --extra-vars "@${PROJECT_DIR}/src/ansible/playbooks/vault.yml" server --become -m fetch -a "src=/etc/rancher/k3s/k3s.yaml dest=~/.kube/homelab.config flat=yes"

  echo "Updating kubeconfig server address..."
  sed -i 's/127.0.0.1/collie.lab.home.arpa/g' ~/.kube/homelab.config

  if [[ "$cluster_context" != "default" ]]; then
    echo "Renaming kubeconfig context from 'default' to '$cluster_context'..."
    sed -i "s/default/$cluster_context/g" ~/.kube/homelab.config
  fi

  echo "Kubeconfig written to ~/.kube/homelab.config"
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  case "$1" in
    -i | --init)
      init
      ;;
    -d | --deploy)
      deploy
      ;;
    -u | --upgrade)
      upgrade
      ;;
    -k | --kubeconfig)
      kubeconfig
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
}

main "$@"
