{
  pkgs,
  ...
}:

let
  bitwardenSshAgentSocket = "/home/masato/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock";
  kritaWayland = pkgs.symlinkJoin {
    name = "krita-wayland";
    paths = [ pkgs.krita ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/krita" --set QT_QPA_PLATFORM wayland
    '';
  };
in
{
  imports = [
    ./hardware-configuration.nix
    ./desktop.nix
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

  # Supplied by nixos-hardware's microsoft-surface-pro-intel profile.
  hardware.microsoft-surface.kernelVersion = "stable";
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.sensor.iio.enable = true;
  services.iptsd.enable = true;
  services.thermald.enable = true;

  networking.hostName = "surface";
  networking.networkmanager.enable = true;

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

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  # The Flatpak build exposes its SSH agent at this socket.
  environment.sessionVariables.SSH_AUTH_SOCK = bitwardenSshAgentSocket;

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
  services.flatpak = {
    enable = true;
    # Bitwarden creates its own XDG Portal autostart entry when "Start
    # automatically on login" is enabled in the app.
    packages = [ "com.bitwarden.desktop" ];
    update.onActivation = true;
  };
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
      KbdInteractiveAuthentication = false;
    };
  };

  environment.systemPackages = with pkgs; [
    appimage-run
    bat
    codex
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
