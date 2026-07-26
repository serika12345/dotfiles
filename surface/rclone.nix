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
    rclone
  ];

  home-manager.users.masato = {
    home.packages = [
      rcloneProtonDriveConfig
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
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/${protonDriveMount} ${rcloneCacheDir}";
        ExecStart = "${pkgs.rclone}/bin/rclone mount ${protonDriveRemote}: %h/${protonDriveMount} --config=${rcloneConfig} --cache-dir=${rcloneCacheDir} --vfs-cache-mode=writes --protondrive-enable-caching=false";
        ExecStop = "/run/wrappers/bin/fusermount3 -uz %h/${protonDriveMount}";
        Restart = "on-failure";
        RestartSec = "10s";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
