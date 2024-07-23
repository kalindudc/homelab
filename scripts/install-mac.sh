#! /bin/bash

brew install python3
brew install go

brew tap hashicorp/tap
brew install hashicorp/tap/terraform

brew tap hashicorp/tap
brew install hashicorp/tap/packer

scripts/install-base.sh

