#! /bin/bash

brew update
brew upgrade

brew tap hashicorp/tap

brew install hashicorp/tap/terraform
brew install sshpass
brew install pipx

pipx ensurepath
