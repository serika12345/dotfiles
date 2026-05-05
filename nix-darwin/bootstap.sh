#!/bin/bash
# install xcode command line tools
xcode-select --install
# install homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# install Lix
curl -sSf -L https://install.lix.systems/lix | sh -s -- install
# setup nix-darwin
# To use Nixpkgs unstable:
sudo nix run nix-darwin/master#darwin-rebuild -- switch
sudo darwin-rebuild switch
