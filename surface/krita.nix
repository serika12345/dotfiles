{ pkgs, ... }:

let
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
  environment.systemPackages = [ kritaWayland ];

  # Keep Krita's brush smoothing defaults reproducible without managing the
  # entire mutable kritarc file. In Krita's config, DistanceMin is the sample
  # count at maximum speed and DistanceMax is the count at minimum speed.
  home-manager.users.masato.home.activation.kritaBrushSmoothing = {
    after = [ "writeBoundary" ];
    before = [ ];
    data = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}"
      kritarc="$config_dir/kritarc"
      kwriteconfig=${pkgs.kdePackages.kconfig}/bin/kwriteconfig6

      run ${pkgs.coreutils}/bin/mkdir -p "$config_dir"
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key LineSmoothingType 3
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key LineSmoothingDistanceKeepAspectRatio --type bool false
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key LineSmoothingDistanceMin 3
      run "$kwriteconfig" --file "$kritarc" --group "<default>" \
        --key LineSmoothingDistanceMax 50
    '';
  };
}
