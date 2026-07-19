{
  config,
  lib,
  pkgs,
  self,
  ...
}:

{
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    (final: prev: {
      xjadeo =
        if prev.stdenv.hostPlatform.isDarwin then
          final.callPackage "${self}/pkgs/xjadeo/package.nix" { }
        else
          prev.xjadeo;
      ghidra =
        if prev.stdenv.hostPlatform.isDarwin then
          final.symlinkJoin {
            name = prev.ghidra.name;
            paths = [ prev.ghidra ];
            postBuild = lib.concatLines [
              "# nixpkgs' Darwin app launcher expects support/ inside the .app,"
              "# but Ghidra keeps the actual runtime tree under lib/ghidra."
              "rm -rf \"$out/Applications/Ghidra.app\""
              "mkdir -p \"$out/Applications/Ghidra.app/Contents/MacOS\""
              "ln -s \"${prev.ghidra}/Applications/Ghidra.app/Contents/Resources\" \"$out/Applications/Ghidra.app/Contents/Resources\""
              "ln -s \"${prev.ghidra}/Applications/Ghidra.app/Contents/Info.plist\" \"$out/Applications/Ghidra.app/Contents/Info.plist\""
              "printf '%s\\n' '#!${final.runtimeShell}' 'exec \"${prev.ghidra}/lib/ghidra/ghidraRun\" \"$@\"' > \"$out/Applications/Ghidra.app/Contents/MacOS/Ghidra\""
              "chmod +x \"$out/Applications/Ghidra.app/Contents/MacOS/Ghidra\""
            ];
            meta = prev.ghidra.meta;
          }
        else
          prev.ghidra;
    })
  ];

  environment.systemPackages = with pkgs; [
    # コーディングエージェント向け
    ripgrep
    fd
    fzf
    bat
    # 一般
    ncdu
    duti
    gh
    glab
    tmux
    ffmpeg
    direnv
    nixfmt
    docker
    colima
    tree
    xjadeo
    furnace
    ghidra
  ];

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # from below, my personal preferences.
  users.users.masato = {
    name = "masato";
    home = "/Users/masato";
  };
  system.primaryUser = "masato";

  # Environment variables
  environment.variables = {
    SSH_AUTH_SOCK = "/Users/masato/.bitwarden-ssh-agent.sock";
  };

  # Environment variables for GUI apps / launchd user processes
  launchd.user.envVariables = {
    SSH_AUTH_SOCK = "/Users/masato/.bitwarden-ssh-agent.sock";
  };

  # SMB client settings for connections from macOS to SMB servers.
  environment.etc."nsmb.conf".text = ''
    [default]
    protocol_vers_map=4
    signing_required=no
  '';

  # -- Begin Finder settings --
  # Show all filename extensions in Finder.
  system.defaults.finder.AppleShowAllExtensions = true;
  # Show hidden files in Finder.
  system.defaults.finder.AppleShowAllFiles = true;
  # Show path bar in Finder.
  system.defaults.finder.ShowPathbar = true;
  # -- End of Finder settings --

  # Keyboard
  # Use F1, F2, etc. keys as standard function keys.
  system.defaults.NSGlobalDomain."com.apple.keyboard.fnState" = true;
  # Set key repeat rate.
  system.defaults.NSGlobalDomain.KeyRepeat = 2;
  # Set delay until key repeat.
  system.defaults.NSGlobalDomain.InitialKeyRepeat = 25;

  # Enable key mapping.
  system.keyboard.enableKeyMapping = true;
  # remap caps lock to control
  system.keyboard.remapCapsLockToControl = true;

  # UI / System Defaults
  # Set dark mode.
  system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark";

  # Set dock to autohide.
  system.defaults.dock.autohide = true;
  # Disable showing recent applications in dock.
  system.defaults.dock.show-recents = false;

  # Show battery percentage in menu bar.
  system.defaults.controlcenter.BatteryShowPercentage = true;

  # Enable three finger drag on trackpad.
  system.defaults.trackpad.TrackpadThreeFingerDrag = true;
  # Enable three finger tap for Look up / Dictionary.
  system.defaults.trackpad.TrackpadThreeFingerTapGesture = 2;

  # hide widgets in desktop
  system.defaults.WindowManager.StandardHideWidgets = true;

  # disable click wallpaper to show desktop
  system.defaults.WindowManager.EnableStandardClickToShowDesktop = false;

  # persistent
  system.defaults.dock.persistent-apps = [
    {
      app = "/System/Applications/Apps.app";
    }
    {
      app = "/System/Applications/Mail.app";
    }
    {
      app = "/Applications/Firefox.app";
    }
    {
      app = "/Applications/Visual Studio Code.app";
    }
    {
      app = "/Applications/ChatGPT.app";
    }
    {
      app = "/System/Applications/Utilities/Terminal.app";
    }
    {
      app = "/Applications/Bitwarden.app";
    }
    {
      app = "/Applications/Proton Authenticator.app"
    }
    {
      app = "/System/Applications/System Settings.app";
    }
  ];

  # Homebrew
  # enable homebrew
  homebrew.enable = true;

  homebrew.taps = [
    "daipeihust/tap"
  ];

  homebrew.brews = [
    "daipeihust/tap/im-select"
    "firefoxpwa"
  ];

  system.activationScripts.homebrew.text = lib.mkBefore ''
    if [ -f "${config.homebrew.prefix}/bin/brew" ]; then
      PATH="${config.homebrew.prefix}/bin:$PATH" \
      sudo \
        --preserve-env=PATH \
        --user=${lib.escapeShellArg config.homebrew.user} \
        --set-home \
        brew trust --quiet --tap daipeihust/tap
    fi
  '';

  homebrew.casks = [
    "visual-studio-code"
    "firefox"
    "ungoogled-chromium"
    "utm"
    "bitwarden"
    "linearmouse"
    "karabiner-elements"
    "adguard"
    "affinity"
    "google-japanese-ime"
    "hex-fiend"
    "onyx"
    "blender"
    "hopper-disassembler"
    "mission-control-plus"
    "hhkb"
    "elgato-game-capture-hd"
    "android-studio"
    "nx-studio"
    "chatgpt"
    "balenaetcher"
    "windows-app"
    "wireshark-app"
    "thaw"
    "proton-drive"
    "protonvpn"
  ];

  # App Store apps
  homebrew.masApps = {
    "LINE" = 539883307;
    "Bandwidth+" = 490461369;
    "SSTP Connect" = 1543667909;
    "Xcode" = 497799835;
    "Proton Authenticator" = 6741758667;
  };

  # Automatically update and upgrade Homebrew packages on activation.
  homebrew.onActivation.autoUpdate = true;
  homebrew.onActivation.upgrade = true;
  homebrew.onActivation.cleanup = "zap";

  system.activationScripts.postActivation.text = lib.mkAfter ''
    target="/Applications/Jadeo.app"
    source="/Applications/Nix Apps/Jadeo.app"

    if [ -e "$source" ]; then
      rm -rf "$target"
      ln -s "$source" "$target"
    fi

    firefoxpwaManifestSource="${config.homebrew.prefix}/opt/firefoxpwa/share/firefoxpwa.json"
    firefoxpwaManifestTargetDir="/Library/Application Support/Mozilla/NativeMessagingHosts"
    firefoxpwaManifestTarget="$firefoxpwaManifestTargetDir/firefoxpwa.json"

    if [ -e "$firefoxpwaManifestSource" ]; then
      mkdir -p "$firefoxpwaManifestTargetDir"
      ln -sfn "$firefoxpwaManifestSource" "$firefoxpwaManifestTarget"
    fi

    firefoxPoliciesDir="/Applications/Firefox.app/Contents/Resources/distribution"

    if [ -d "/Applications/Firefox.app" ]; then
      mkdir -p "$firefoxPoliciesDir"
      install -m 0644 ${
        pkgs.writeText "firefox-policies.json" (
          builtins.toJSON {
            policies = {
              ExtensionSettings = {
                "firefoxpwa@filips.si" = {
                  installation_mode = "normal_installed";
                  install_url = "https://addons.mozilla.org/firefox/downloads/latest/pwas-for-firefox/latest.xpi";
                };
              };
            };
          }
        )
      } "$firefoxPoliciesDir/policies.json"
    fi
  '';
}
