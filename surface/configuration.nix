{
  codexPackage,
  pkgs,
  ...
}:

let
  bitwardenSshAgentSocket = "/home/masato/.bitwarden-ssh-agent.sock";
  bitwardenDesktop = pkgs.bitwarden-desktop.overrideAttrs (_oldAttrs: {
    # nixpkgs does not currently provide a substitute for this derivation in
    # the pinned revision. Skip the Rust test phase to keep local builds short.
    doCheck = false;
  });
  kritaWayland = pkgs.symlinkJoin {
    name = "krita-wayland";
    paths = [ pkgs.krita ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/krita" --set QT_QPA_PLATFORM wayland
    '';
  };
  sshSuspendInhibitor = pkgs.writeShellApplication {
    name = "ssh-suspend-inhibitor";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = ''
      has_ssh_session() {
        local session

        while read -r session _; do
          if
            [ "$(loginctl show-session "$session" --property=Service --value)" = "sshd" ] &&
              [ "$(loginctl show-session "$session" --property=State --value)" = "active" ]
          then
            return 0
          fi
        done < <(loginctl list-sessions --no-legend)

        return 1
      }

      case "''${1:-monitor}" in
        monitor)
          while true; do
            if has_ssh_session; then
              systemd-inhibit \
                --what=sleep \
                --who=sshd \
                --why="An SSH session is active" \
                --mode=block \
                "$0" wait
            else
              sleep 1
            fi
          done
          ;;
        wait)
          while has_ssh_session; do
            sleep 1
          done
          ;;
        *)
          echo "usage: ssh-suspend-inhibitor [monitor|wait]" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  imports = [
    ./hardware-configuration.nix
    ./desktop.nix
    ./rclone.nix
  ];

  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 5;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # The Surface buttons are GPIO devices. If soc_button_array wins the module
  # loading race, it probes before Ice Lake pinctrl is ready and never creates
  # the power/volume input devices.
  boot.extraModprobeConfig = ''
    softdep soc_button_array pre: pinctrl_icelake
  '';

  # The power and volume buttons are separate gpio-keys devices with the same
  # ID. keyd shares state between devices matched by one configuration, allowing
  # the Windows-style button chord while preserving each button's normal action.
  services.keyd = {
    enable = true;
    keyboards.surfaceButtons = {
      ids = [ "0001:0001" ];
      settings = {
        global.chord_timeout = 150;
        main."power+volumeup" = "S-print";
      };
    };
  };

  # Supplied by nixos-hardware's microsoft-surface-pro-intel profile.
  hardware.microsoft-surface.kernelVersion = "stable";
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.sensor.iio.enable = true;
  services.iptsd = {
    enable = true;
    config.Touchscreen = {
      DisableOnPalm = true;
      DisableOnStylus = true;
    };
  };
  services.thermald.enable = true;

  networking.hostName = "surface";
  networking.networkmanager.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    wideArea = false;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # GNOME normally handles the button while a session is active. Keep logind
  # as a fallback for GDM, TTY sessions, or when GNOME is not running.
  services.logind.settings.Login.HandlePowerKey = "suspend";

  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "ja_JP.UTF-8";
    LC_IDENTIFICATION = "ja_JP.UTF-8";
    LC_MEASUREMENT = "ja_JP.UTF-8";
    LC_MONETARY = "ja_JP.UTF-8";
    LC_NAME = "ja_JP.UTF-8";
    LC_NUMERIC = "ja_JP.UTF-8";
    LC_PAPER = "ja_JP.UTF-8";
    LC_TELEPHONE = "ja_JP.UTF-8";
    LC_TIME = "ja_JP.UTF-8";
  };

  console.useXkbConfig = true;
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
    options = "ctrl:nocaps";
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
  ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # Prefer shorter wall-clock rebuilds on the Surface when packages are not
    # substituted from cache.
    max-jobs = "auto";
    cores = 0;
  };
  nixpkgs.config = {
    allowUnfree = true;
    # Required by the Electron version used by bitwarden-desktop in the pinned
    # nixpkgs revision.
    permittedInsecurePackages = [ "electron-39.8.10" ];
  };

  # Bitwarden Desktop exposes its SSH agent at this socket on Linux.
  environment.sessionVariables.BITWARDEN_SSH_AUTH_SOCK = bitwardenSshAgentSocket;
  environment.extraInit = ''
    if [ -z "''${SSH_AUTH_SOCK:-}" ]; then
      export SSH_AUTH_SOCK="${bitwardenSshAgentSocket}"
    fi
  '';

  services.displayManager.autoLogin.enable = false;
  services.getty.autologinUser = null;

  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users.masato = {
    isNormalUser = true;
    description = "Local user";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJauOxj4XI7YW2AQde7bvW+a7J9hSXRbe6nWTtKSFXs4"
    ];
  };

  home-manager.backupFileExtension = "backup";
  home-manager.users.masato = {
    home.stateVersion = "26.05";

    programs.bash.enable = true;
    programs.git = {
      enable = true;
      settings.user = {
        email = "281916063+serika12345@users.noreply.github.com";
        name = "serika12345";
      };
    };
    programs.gh = {
      enable = true;
      gitCredentialHelper.enable = true;
    };
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };

  programs.firefox.enable = true;
  xdg.mime.defaultApplications = {
    "text/html" = [ "firefox.desktop" ];
    "x-scheme-handler/http" = [ "firefox.desktop" ];
    "x-scheme-handler/https" = [ "firefox.desktop" ];
    "x-scheme-handler/about" = [ "firefox.desktop" ];
    "x-scheme-handler/unknown" = [ "firefox.desktop" ];
  };

  virtualisation.docker.enable = true;
  programs.appimage = {
    enable = true;
    binfmt = true;
  };
  programs.direnv.enable = true;
  programs.nix-ld.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "masato" ];
      AllowAgentForwarding = true;
      KbdInteractiveAuthentication = false;
    };
  };

  # Keep the machine awake while logind knows about at least one OpenSSH
  # session. OpenSSH registers its sessions with logind through PAM.
  systemd.services.ssh-suspend-inhibitor = {
    description = "Prevent suspend while an SSH session is active";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-logind.service" ];
    wants = [ "systemd-logind.service" ];
    serviceConfig = {
      ExecStart = "${sshSuspendInhibitor}/bin/ssh-suspend-inhibitor";
      Restart = "always";
      RestartSec = 1;
    };
  };

  environment.systemPackages = with pkgs; [
    appimage-run
    bat
    bitwardenDesktop
    codexPackage
    direnv
    fd
    fzf
    git
    htop
    jq
    kritaWayland
    nettools
    nixfmt
    nodejs_24
    python315
    ripgrep
    tree
    unzip
    uv
    vim
    vscode
    wget
    zip
  ];

  system.stateVersion = "26.05";
}
