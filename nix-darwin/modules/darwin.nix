{
  config,
  lib,
  pkgs,
  self,
  codexPackage,
  ...
}:
let
  macosNixCachePublicKey = lib.removeSuffix "\n" (builtins.readFile ../macos-nix-cache-public-key);
  macosNixCacheBitwardenItemId = "/Users/masato/.config/nix/macos-nix-cache-bitwarden-item-id";
  macosNixCacheBitwardenCli = "/opt/homebrew/bin/bw";
  macosNixCacheConfigureBitwarden = pkgs.writeShellScriptBin "nix-cache-configure-bitwarden" ''
    set -eu

    if [ "$#" -ne 1 ]; then
      echo "Usage: nix-cache-configure-bitwarden BITWARDEN_ITEM_UUID" >&2
      exit 64
    fi

    case "$1" in
      ????????-????-????-????-????????????) ;;
      *)
        echo "BITWARDEN_ITEM_UUID must be a UUID." >&2
        exit 64
        ;;
    esac

    config_directory="$(${pkgs.coreutils}/bin/dirname '${macosNixCacheBitwardenItemId}')"
    ${pkgs.coreutils}/bin/install -d -m 700 "$config_directory"
    temporary_file="$(${pkgs.coreutils}/bin/mktemp "$config_directory/.macos-nix-cache-item.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$temporary_file"' EXIT HUP INT TERM
    printf '%s\n' "$1" > "$temporary_file"
    ${pkgs.coreutils}/bin/chmod 600 "$temporary_file"
    ${pkgs.coreutils}/bin/mv -f "$temporary_file" '${macosNixCacheBitwardenItemId}'
    trap - EXIT HUP INT TERM

    echo "Configured the macOS Nix cache signing-key item."
  '';
  macosNixCacheBuild = pkgs.writeShellScriptBin "nix-cache-build" ''
    set -euo pipefail

    if [ "$#" -eq 0 ]; then
      echo "Usage: nix-cache-build INSTALLABLE [INSTALLABLE ...]" >&2
      exit 64
    fi

    if [ ! -x '${macosNixCacheBitwardenCli}' ]; then
      echo "Bitwarden CLI is not installed at ${macosNixCacheBitwardenCli}." >&2
      exit 69
    fi

    if [ ! -r '${macosNixCacheBitwardenItemId}' ]; then
      echo "Configure the Bitwarden signing-key item first:" >&2
      echo "  nix-cache-configure-bitwarden BITWARDEN_ITEM_UUID" >&2
      exit 78
    fi

    item_id="$(${pkgs.coreutils}/bin/cat '${macosNixCacheBitwardenItemId}')"
    output_paths="$(${config.nix.package}/bin/nix build --print-out-paths "$@")"
    key_file="$(${pkgs.coreutils}/bin/mktemp "''${TMPDIR:-/tmp}/macos-nix-cache-key.XXXXXX")"
    cleanup() {
      ${pkgs.coreutils}/bin/rm -f "$key_file"
      '${macosNixCacheBitwardenCli}' lock >/dev/null 2>&1 || true
    }
    trap cleanup EXIT HUP INT TERM

    bw_session="$('${macosNixCacheBitwardenCli}' unlock --raw)"
    BW_SESSION="$bw_session" '${macosNixCacheBitwardenCli}' sync >/dev/null
    BW_SESSION="$bw_session" '${macosNixCacheBitwardenCli}' get password "$item_id" > "$key_file"
    ${pkgs.coreutils}/bin/chmod 600 "$key_file"

    actual_public_key="$(${config.nix.package}/bin/nix key convert-secret-to-public < "$key_file")"
    if [ "$actual_public_key" != '${macosNixCachePublicKey}' ]; then
      echo "The Bitwarden item does not contain the configured Nix cache signing key." >&2
      exit 65
    fi

    while IFS= read -r output_path; do
      [ -n "$output_path" ] || continue
      case "$output_path" in
        /nix/store/*) ;;
        *)
          echo "Unexpected Nix build output: $output_path" >&2
          exit 65
          ;;
      esac

      {
        printf '%s\n' "$output_path"
        ${config.nix.package}/bin/nix-store -qR "$output_path"
      } | ${pkgs.coreutils}/bin/sort -u | ${config.nix.package}/bin/nix store sign --stdin --key-file "$key_file"

      ${config.nix.package}/bin/nix copy --to ssh://nixos-cache "$output_path"
    done <<EOF
    $output_paths
    EOF
  '';
in
{
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    (final: prev: {
      xjadeo =
        if prev.stdenv.hostPlatform.isDarwin then
          final.callPackage "${self}/pkgs/xjadeo/package.nix" { }
        else
          prev.xjadeo;
      proton-drive-cli = final.callPackage "${self}/pkgs/proton-drive-cli/package.nix" { };
      mocktab = final.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "mocktab";
        version = "0.4.0";

        src = final.fetchurl {
          url = "https://github.com/Cyzor/tablet-driver/releases/download/v${finalAttrs.version}/MockTab-${finalAttrs.version}.dmg";
          hash = "sha256-qVNbNQ73lPqM48TMrwf3nTDHKVaehQLkkNnkJt8x7Ro=";
        };

        # The release image uses APFS, which nixpkgs' undmg cannot unpack.
        # Preserve symlinks and omit macOS xattr pseudo-files so the notarized
        # application bundle remains byte-for-byte signed.
        nativeBuildInputs = [ final._7zz ];
        sourceRoot = ".";
        unpackCmd = "7zz x -snld -xr'!*:com.apple.*' $curSrc";

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/Applications"
          cp -R MockTab.app "$out/Applications/"

          runHook postInstall
        '';

        dontFixup = true;

        meta = {
          description = "Open-source macOS driver for unsupported Wacom tablets";
          homepage = "https://mocktab.org/";
          license = lib.licenses.gpl3Plus;
          platforms = lib.platforms.darwin;
          sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
        };
      });
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
    codexPackage
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
    proton-drive-cli
    mocktab
    macosNixCacheConfigureBitwarden
    macosNixCacheBuild
  ];

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Normal Nix commands only consume this cache. `nix-cache-build` explicitly
  # signs and publishes a selected output closure without project-side code.
  nix.settings.extra-substituters = [
    "http://192.168.100.5:5000"
  ];
  nix.settings.extra-trusted-public-keys = [
    macosNixCachePublicKey
  ];
  nix.settings.trusted-users = lib.mkAfter [ "masato" ];

  # Fail closed: every build is sandboxed unless its derivation explicitly
  # declares an administrator-approved host dependency below.
  nix.settings.sandbox = true;
  nix.settings.sandbox-fallback = false;

  # Krita's iPadOS target derivations use the exact local Xcode toolchain as
  # their only non-store input. Keep it off sandbox-paths so only derivations
  # that explicitly declare __impureHostDeps can see it.
  nix.settings.extra-allowed-impure-host-deps = [
    "/Applications/Xcode.app"
  ];

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  networking = {
    computerName = "macbookair";
    hostName = "macbookair";
    localHostName = "macbookair";
  };

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
      app = "/Applications/Proton Authenticator.app";
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
    "bitwarden-cli"
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
    "raspberry-pi-imager"
    "fujitsu-scansnap-home"
    "krita"
    "kde-connect"
    "altserver"
  ];

  # App Store apps
  homebrew.masApps = {
    "LINE" = 539883307;
    "Bandwidth+" = 490461369;
    "SSTP Connect" = 1543667909;
    "Xcode" = 497799835;
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
