{ pkgs, ... }:

let
  calibrationStateDir = "/var/lib/surface-pen-calibration";
  calibrationStateFile = "${calibrationStateDir}/matrix";

  surfacePenUdevRules = pkgs.writeTextFile {
    name = "surface-pen-calibration-udev-rules";
    destination = "/etc/udev/rules.d/69-surface-pen-calibration.rules";
    text = ''
      ACTION!="remove", SUBSYSTEM=="input", KERNEL=="event[0-9]*", \
        ATTRS{name}=="IPTSD Virtual Stylus 045E:099F", TAG+="uaccess"
    '';
  };

  readSurfacePenCalibration = pkgs.writeShellApplication {
    name = "surface-pen-calibration-read";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      state_file=${calibrationStateFile}
      identity="1 0 0 0 1 0"

      if [[ ! -r "$state_file" ]]; then
        printf '%s\n' "$identity"
        exit 0
      fi

      read -r -a values < "$state_file"
      if [[ "''${#values[@]}" -ne 6 ]]; then
        printf '%s\n' "$identity"
        exit 0
      fi

      number_pattern='^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$'
      for value in "''${values[@]}"; do
        if [[ ! "$value" =~ $number_pattern ]]; then
          printf '%s\n' "$identity"
          exit 0
        fi
      done

      printf '%s\n' "''${values[*]}"
    '';
  };

  installSurfacePenCalibration = pkgs.writeShellApplication {
    name = "surface-pen-calibration-install";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.iptsd
      pkgs.systemd
    ];
    text = ''
      state_dir=${calibrationStateDir}
      state_file=${calibrationStateFile}

      if [[ "$EUID" -ne 0 ]]; then
        echo "This helper must run as root through pkexec." >&2
        exit 1
      fi

      install -d -m 0755 -o root -g root "$state_dir"

      if [[ "''${1:-}" == "--reset" ]]; then
        if [[ "$#" -ne 1 ]]; then
          echo "usage: surface-pen-calibration-install --reset" >&2
          exit 2
        fi
        rm -f "$state_file"
      else
        if [[ "$#" -ne 6 ]]; then
          echo "usage: surface-pen-calibration-install a b c d e f" >&2
          exit 2
        fi

        number_pattern='^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][-+]?[0-9]+)?$'
        for value in "$@"; do
          if [[ ! "$value" =~ $number_pattern ]]; then
            echo "Invalid calibration matrix value: $value" >&2
            exit 2
          fi
        done

        temporary="$(mktemp "$state_dir/.matrix.XXXXXX")"
        trap 'rm -f "$temporary"' EXIT
        printf '%s\n' "$*" > "$temporary"
        chmod 0644 "$temporary"
        chown root:root "$temporary"
        mv -f "$temporary" "$state_file"
        trap - EXIT
      fi

      # The calibration property is read when libinput discovers the device.
      # Recreating IPTSD's uinput devices makes Mutter pick up the new matrix.
      udevadm control --reload-rules
      iptsd-systemd -t touchscreen -- restart
    '';
  };

  surfacePenCalibrate = pkgs.stdenv.mkDerivation {
    pname = "surface-pen-calibrate";
    version = "0.2.0";
    src = ./pkgs/surface-pen-calibrate;

    nativeBuildInputs = [
      pkgs.cmake
      pkgs.ninja
      pkgs.qt6.wrapQtAppsHook
    ];
    buildInputs = [ pkgs.qt6.qtbase ];

    # GNOME 50 delivers only the first tablet proximity cycle to Qt's native
    # Wayland backend on this device. XWayland receives every press/release and
    # preserves the absolute tablet coordinates needed for calibration.
    qtWrapperArgs = [
      "--set"
      "QT_QPA_PLATFORM"
      "xcb"
    ];

    cmakeFlags = [
      (pkgs.lib.cmakeFeature "INSTALL_HELPER_PATH" "${installSurfacePenCalibration}/bin/surface-pen-calibration-install")
      (pkgs.lib.cmakeFeature "PKEXEC_PATH" "/run/wrappers/bin/pkexec")
    ];

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      ctest --output-on-failure
      runHook postCheck
    '';
  };
in
{
  environment.systemPackages = [ surfacePenCalibrate ];
  services.udev.packages = [ surfacePenUdevRules ];

  systemd.tmpfiles.rules = [
    "d ${calibrationStateDir} 0755 root root -"
  ];

  systemd.services.surface-pen-calibration-access = {
    description = "Refresh access to the IPTSD virtual stylus";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];
    restartTriggers = [ surfacePenUdevRules ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.systemd}/bin/udevadm control --reload
      ${pkgs.systemd}/bin/udevadm trigger --action=change --subsystem-match=input --sysname-match='event*'
      ${pkgs.systemd}/bin/udevadm settle
    '';
  };

  # libinput reads this property when IPTSD creates its virtual stylus. The
  # helper returns the identity matrix until the calibration app stores one.
  services.udev.extraRules = ''
    ACTION!="remove", SUBSYSTEM=="input", KERNEL=="event[0-9]*", \
      ATTRS{name}=="IPTSD Virtual Stylus 045E:099F", \
      PROGRAM="${readSurfacePenCalibration}/bin/surface-pen-calibration-read", \
      ENV{LIBINPUT_CALIBRATION_MATRIX}="%c"
  '';
}
