{
  lib,
  pkgs,
  ...
}:

let
  protonDriveRemote = "protondrive";
  protonDriveMount = "ProtonDrive";
  rcloneConfig = "%h/.config/rclone/rclone.conf";
  rcloneCacheDir = "%h/.cache/rclone/${protonDriveRemote}";
  waitForSynchronizedClock = pkgs.writeShellScript "wait-for-synchronized-clock" ''
    for _attempt in $(${pkgs.coreutils}/bin/seq 1 60); do
      if
        [ "$(${pkgs.systemd}/bin/timedatectl show --property=NTPSynchronized --value)" = yes ]
      then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done

    echo "Timed out waiting for the system clock to synchronize" >&2
    exit 1
  '';
  scanHome = pkgs.writeShellScriptBin "scanhome" ''
    set -euo pipefail

    exec ${pkgs.ncdu}/bin/ncdu \
      --one-file-system \
      --exclude "CloudStorage" \
      --exclude "Mobile Documents" \
      --exclude "${protonDriveMount}" \
      --exclude "Proton Drive" \
      --exclude "OneDrive" \
      --exclude "Google Drive" \
      --exclude "Dropbox" \
      "$HOME"
  '';
  rcloneProtonDriveConfig = pkgs.writeShellScriptBin "rclone-protondrive-config" ''
    set -euo pipefail

    config_file="''${XDG_CONFIG_HOME:-$HOME/.config}/rclone/rclone.conf"
    config_dir="''${config_file%/*}"
    mkdir -p "$config_dir"

    printf '%s\n' \
      'Create or update an rclone Proton Drive remote named "protondrive".' \
      "" \
      "Suggested answers:" \
      "  n) New remote" \
      "  name> protondrive" \
      "  Storage> protondrive" \
      "  user> your Proton account" \
      "  password> type manually" \
      "  2fa> current code, or leave empty if unused" \
      "" \
      "Credentials are stored in your user rclone.conf, not in Nix."

    exec ${pkgs.rclone}/bin/rclone config --config "$config_file"
  '';
in
{
  programs.fuse.enable = true;

  environment.systemPackages = with pkgs; [
    ncdu
    rclone
  ];

  home-manager.users.masato = {
    home.packages = [
      rcloneProtonDriveConfig
      scanHome
    ];

    systemd.user.services.rclone-protondrive = {
      Unit = {
        Description = "Mount Proton Drive with rclone";
        Documentation = "https://rclone.org/protondrive/";
        After = [ "network-online.target" ];
        ConditionPathExists = rcloneConfig;
      };

      Service = {
        Type = "notify";
        Environment = [
          "PATH=/run/wrappers/bin:${lib.makeBinPath [ pkgs.fuse3 ]}"
        ];
        ExecCondition = "${pkgs.gnugrep}/bin/grep -Fxq '[${protonDriveRemote}]' ${rcloneConfig}";
        ExecStartPre = [
          waitForSynchronizedClock
          "${pkgs.coreutils}/bin/mkdir -p %h/${protonDriveMount} ${rcloneCacheDir}"
        ];
        ExecStart = "${pkgs.rclone}/bin/rclone mount ${protonDriveRemote}: %h/${protonDriveMount} --config=${rcloneConfig} --cache-dir=${rcloneCacheDir} --vfs-cache-mode=writes --protondrive-enable-caching=false";
        ExecStop = "/run/wrappers/bin/fusermount3 -uz %h/${protonDriveMount}";
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "90s";
        TimeoutStopSec = "5s";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
