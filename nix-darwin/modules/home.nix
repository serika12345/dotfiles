{ config, pkgs, ... }:

{
  home = {
    username = "masato";
    homeDirectory = "/Users/masato";
    stateVersion = "23.11";
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
      KeepAlive = {
        SuccessfulExit = false;
      };
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
