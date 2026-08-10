{ config, pkgs, ... }:

let
  bitwardenSshAgentSocket = "/Users/masato/.bitwarden-ssh-agent.sock";
  scanHome = pkgs.writeShellScriptBin "scanhome" ''
    set -euo pipefail

    exec ${pkgs.ncdu}/bin/ncdu \
      --one-file-system \
      --exclude "CloudStorage" \
      --exclude "Mobile Documents" \
      --exclude "ProtonDrive" \
      --exclude "Proton Drive" \
      --exclude "OneDrive" \
      --exclude "Google Drive" \
      --exclude "Dropbox" \
      "$HOME"
  '';
in

{
  home = {
    username = "masato";
    homeDirectory = "/Users/masato";
    stateVersion = "23.11";
    packages = [
      scanHome
    ];
  };

  launchd.agents.colima = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.colima}/bin/colima"
        "start"
        "--foreground"
      ];
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/colima.out.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/colima.err.log";
      EnvironmentVariables = {
        PATH = "${pkgs.colima}/bin:${pkgs.docker}/bin:/usr/local/bin:/usr/bin:/bin";
      };
    };
  };

  programs.zsh = {
    enable = true;
    shellAliases = {
      ls = "ls -G";
    };
    initContent = ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';
  };

  programs.git = {
    enable = true;
    ignores = [
      ".DS_Store"
    ];
    settings = {
      user = {
        name = "serika12345";
        email = "281916063+serika12345@users.noreply.github.com";
      };
    };
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "${config.home.homeDirectory}/.colima/ssh_config" ];
    matchBlocks = {
      "*" = {
        forwardAgent = false;
        addKeysToAgent = "no";
        compression = false;
        serverAliveInterval = 120;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
        extraOptions.GSSAPIAuthentication = "no";
      };

      "github.com" = {
        identityAgent = bitwardenSshAgentSocket;
      };

      "nixos" = {
        hostname = "nixos.local";
        user = "masato";
        forwardAgent = true;
        identityAgent = bitwardenSshAgentSocket;
      };

      # Reuse the Bitwarden SSH Agent's existing NixOS key. On the cache
      # account, sshd limits this same key to the cache store protocol.
      "nixos-cache" = {
        hostname = "nixos.local";
        user = "macos-nix-cache";
        forwardAgent = false;
        identityAgent = bitwardenSshAgentSocket;
      };

      "surface" = {
        hostname = "surface.local";
        user = "masato";
        forwardAgent = true;
        identityAgent = bitwardenSshAgentSocket;
      };

      "surface.local" = {
        user = "masato";
      };

      "192.168.100.7" = { };

      "192.168.100.6" = {
        user = "masato";
      };

      "192.168.100.5" = {
        user = "masato";
        forwardAgent = true;
      };

      "192.168.100.1" = {
        extraOptions.PreferredAuthentications = "password";
      };
    };
  };

  programs.vim = {
    enable = true;
    extraConfig = ''
      set number
      syntax on
      set backspace=indent,eol,start
      set expandtab
      set tabstop=2
      set shiftwidth=2
      set softtabstop=2
    '';
  };
}
