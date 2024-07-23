#! /bin/bash

brew install python3
brew install go

brew tap hashicorp/tap
brew install hashicorp/tap/terraform

brew tap hashicorp/tap
brew install hashicorp/tap/packer

brew tap shopify/shopify
brew install ejson

brew install go-task/tap/go-task

brew install fluxcd/tap/flux

brew tap weaveworks/tap
brew install weaveworks/tap/gitops

brew install jq

brew install kubectl

brew install pre-commit

brew install yq

brew install sops

brew install helm

brew install kustomize

brew install stern

./install-base.sh
./setup.sh
