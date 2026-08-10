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

  nixProjectSleep = pkgs.writeShellScriptBin "nix-project-sleep" ''
    set -euo pipefail

    usage() {
      printf '%s\n' \
        'Usage: nix-project-sleep [--dry-run] PROJECT...' \
        'Remove nix-direnv flake-profile GC roots for inactive projects, then run Nix GC.' \
        'Leave each project directory and stop its development processes before running this.'
    }

    dry_run=0
    case "''${1:-}" in
      --dry-run)
        dry_run=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
    esac

    if [ "$#" -eq 0 ]; then
      usage >&2
      exit 2
    fi

    project_dirs=()
    for input_dir in "$@"; do
      if [ ! -d "$input_dir" ]; then
        printf 'nix-project-sleep: not a directory: %s\n' "$input_dir" >&2
        exit 2
      fi
      project_dirs+=("$(cd "$input_dir" && pwd -P)")
    done

    for project_dir in "''${project_dirs[@]}"; do
      direnv_dir="$project_dir/.direnv"
      if [ ! -d "$direnv_dir" ]; then
        printf 'nix-project-sleep: no .direnv directory: %s\n' "$project_dir" >&2
        continue
      fi

      if [ "$dry_run" -eq 1 ]; then
        printf 'Would remove nix-direnv roots in %s:\n' "$project_dir"
        ${pkgs.findutils}/bin/find "$direnv_dir" -maxdepth 1 -type l \
          \( -name 'flake-profile' -o -name 'flake-profile-*-link' \) -print
      else
        printf 'Removing nix-direnv roots in %s:\n' "$project_dir"
        ${pkgs.findutils}/bin/find "$direnv_dir" -maxdepth 1 -type l \
          \( -name 'flake-profile' -o -name 'flake-profile-*-link' \) -print -delete
      fi
    done

    if [ "$dry_run" -eq 1 ]; then
      exec ${pkgs.nix}/bin/nix-collect-garbage --dry-run
    else
      exec ${pkgs.nix}/bin/nix-collect-garbage
    fi
  '';
in

{
  home = {
    username = "masato";
    homeDirectory = "/Users/masato";
    stateVersion = "23.11";
    packages = [
      scanHome
      nixProjectSleep
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
