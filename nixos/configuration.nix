{
  codexPackage,
  config,
  pkgs,
  ...
}:
let
  desktopModule = ./desktop/gnome.nix;
  bitwardenSshAgentSocket = "/home/masato/.bitwarden-ssh-agent.sock";
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
  imports = [
    ./hardware-configuration.nix
    ./macos-nix-cache.nix
    desktopModule
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 5;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
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

  # Set your time zone.
  time.timeZone = "Asia/Tokyo";

  # Select internationalisation properties.
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

  # TTYで日本語入力を有効化
  console.useXkbConfig = true;

  # noto
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
    # CUDAのバイナリキャッシュ
    substituters = [
      "https://cache.nixos-cuda.org"
      "https://cache.nixos.org/"
    ];
    trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
  };

  # Bitwarden Desktop exposes its SSH agent at this socket on Linux.
  environment.sessionVariables.BITWARDEN_SSH_AUTH_SOCK = bitwardenSshAgentSocket;
  environment.extraInit = ''
    if [ -z "''${SSH_AUTH_SOCK:-}" ]; then
      export SSH_AUTH_SOCK="${bitwardenSshAgentSocket}"
    fi
  '';

  # Enable OpenGL
  hardware.graphics.enable = true;

  # AppImage support
  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  # サスペンドやスリープを無効化(物理ボタンとかのイベントに対して起きる反応を制御するもの)
  services.logind = {
    settings.Login = {
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      HandleLidSwitch = "ignore";
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      IdleAction = "ignore";
    };
  };

  # 念のため systemd 側でも sleep 系を禁止
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = false;
    AllowHybridSleep = false;
    AllowSuspendThenHibernate = false;
  };

  # Load nvidia driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {

    # Modesetting is required.
    modesetting.enable = true;

    # Nvidia power management. Experimental, and can cause sleep/suspend to fail.
    # Enable this if you have graphical corruption issues or application crashes after waking
    # up from sleep. This fixes it by saving the entire VRAM memory to /tmp/ instead
    # of just the bare essentials.
    powerManagement.enable = false;

    # Fine-grained power management. Turns off GPU when not in use.
    # Experimental and only works on modern Nvidia GPUs (Turing or newer).
    powerManagement.finegrained = false;

    # Use the NVidia open source kernel module (not to be confused with the
    # independent third-party "nouveau" open source driver).
    # Support is limited to the Turing and later architectures. Full list of
    # supported GPUs is at:
    # https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus
    # Only available from driver 515.43.04+
    open = false;

    # Enable the Nvidia settings menu,
    # accessible via `nvidia-settings`.
    nvidiaSettings = true;

    # Optionally, you may need to select the appropriate driver version for your specific GPU.
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # enable thunderbolt support
  services.hardware.bolt.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "jp";
    variant = "";
    options = "ctrl:nocaps";
  };

  # Disable autologin to avoid session conflicts
  services.displayManager.autoLogin.enable = false;
  services.getty.autologinUser = null;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Enable Docker
  virtualisation.docker.enable = true;
  # Enable the NVIDIA Container Toolkit to allow Docker containers to use the GPU.
  hardware.nvidia-container-toolkit.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
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
    packages = with pkgs; [
      #  thunderbird
    ];
  };

  home-manager.backupFileExtension = "backup";

  # JISキーボード及び日本語IMEを使用するための設定
  home-manager.users.masato =
    { ... }:
    {
      home.stateVersion = "25.11";

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
        gitCredentialHelper = {
          enable = true;
        };
      };

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      home.packages = [
        scanHome
      ];

      home.file.".codex/AGENTS.md".source = ../codex/AGENTS.md;
    };

  # Install firefox.
  programs.firefox.enable = true;

  xdg.mime.defaultApplications = {
    "text/html" = [ "firefox.desktop" ];
    "x-scheme-handler/http" = [ "firefox.desktop" ];
    "x-scheme-handler/https" = [ "firefox.desktop" ];
    "x-scheme-handler/about" = [ "firefox.desktop" ];
    "x-scheme-handler/unknown" = [ "firefox.desktop" ];
  };

  # Allow unfree packages and enable CUDA support
  nixpkgs.config.allowUnfree = true;
  # 依存するすべてのパッケージのビルドレシピが変わってしまい、ビルドに時間がかかるため、CUDAサポートは有効化しない。
  # nixpkgs.config.cudaSupport = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    python315
    uv
    nodejs_24
    vim
    git
    wget
    ripgrep
    fd
    jq
    fzf
    bat
    zip
    unzip
    tree
    htop
    nettools
    ncdu
    vscode
    direnv
    nixfmt
    bitwarden-desktop
    codexPackage
    appimage-run
  ];

  # direnv有効化
  programs.direnv.enable = true;

  # vscodeで必要 https://wiki.nixos.org/wiki/Visual_Studio_Code
  programs.nix-ld.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    PermitRootLogin = "no";
    AllowUsers = [ "masato" ];
    AllowAgentForwarding = true;
    KbdInteractiveAuthentication = false;
  };

  # Enable Samba file sharing on the local network.
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "server string" = "nixos";
        "workgroup" = "WORKGROUP";
        "security" = "user";
        "map to guest" = "Bad User";
      };

      masato = {
        "path" = "/home/masato";
        "browseable" = "yes";
        "read only" = "no";
        "valid users" = "masato";
        "create mask" = "0664";
        "directory mask" = "0775";
      };
    };
  };

  # Makes the Samba server discoverable from modern Windows clients.
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 7860 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
