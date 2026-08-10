{
  config,
  lib,
  pkgs,
  ...
}:
let
  cacheAddress = "192.168.100.5";
  cacheDirectory = "/var/lib/macos-nix-cache";
  cacheGroup = "macos-nix-cache";
  cacheInterface = "enp0s31f6";
  cacheMinimumFreeKiB = 20 * 1024 * 1024;
  cachePort = 5000;
  cacheUser = "macos-nix-cache";

  # The signing private key intentionally lives only on the Mac, outside the
  # repository and outside the Nix store.
  cachePublicKey = lib.removeSuffix "\n" (builtins.readFile ./macos-nix-cache-public-key);
  administratorKeys = config.users.users.masato.openssh.authorizedKeys.keys;

  # The writer can only speak the legacy Nix store protocol.  It is mapped to a
  # separate file binary cache, so imported macOS outputs cannot affect this
  # NixOS machine's own /nix/store or be removed by its garbage collector.
  uploadProgram = pkgs.writeShellScript "macos-nix-cache-upload" ''
    set -eu

    if [ "''${SSH_ORIGINAL_COMMAND-}" != "nix-store --serve --write" ]; then
      echo "Only the Nix SSH store upload protocol is available." >&2
      exit 126
    fi

    set -- $(${pkgs.coreutils}/bin/df -Pk "${cacheDirectory}" | ${pkgs.coreutils}/bin/tail -n 1)
    available_kib="$4"
    if [ "$available_kib" -lt ${toString cacheMinimumFreeKiB} ]; then
      echo "macOS Nix cache has less than 20 GiB free; refusing new uploads." >&2
      exit 75
    fi

    umask 0027
    exec ${config.nix.package}/bin/nix-store \
      --serve \
      --write \
      --store 'file://${cacheDirectory}'
  '';
in
{
  assertions = [
    {
      assertion = builtins.match "macos-nix-cache-1:[A-Za-z0-9+/]{43}=" cachePublicKey != null;
      message = "nixos/macos-nix-cache-public-key must contain the macos-nix-cache-1 public key only.";
    }
    {
      assertion = administratorKeys != [ ];
      message = "The macOS cache writer requires at least one NixOS administrator SSH key.";
    }
    {
      assertion = !(builtins.elem cachePort config.networking.firewall.allowedTCPPorts);
      message = "The macOS Nix cache port must be opened only on ${cacheInterface}, not globally.";
    }
  ];

  users.groups.${cacheGroup} = { };
  users.users.${cacheUser} = {
    isSystemUser = true;
    group = cacheGroup;
    home = cacheDirectory;
    createHome = false;
    shell = pkgs.bashInteractive;
    # The existing Bitwarden-backed administrator key can authenticate here,
    # but this account always has the forced cache-only command below.
    openssh.authorizedKeys.keys = map (
      key: ''restrict,command="${uploadProgram}" ${key}''
    ) administratorKeys;
  };

  # nginx needs read/traverse access only; the restricted writer is the only
  # account that can create or replace cache objects.
  users.users.nginx.extraGroups = [ cacheGroup ];
  systemd.tmpfiles.rules = [
    "d ${cacheDirectory} 0750 ${cacheUser} ${cacheGroup} -"
  ];

  services.openssh.settings.AllowUsers = lib.mkAfter [ cacheUser ];

  services.nginx = {
    enable = true;
    virtualHosts."macos-nix-cache" = {
      # No wildcard or IPv6 listener: this cache is limited to the private LAN.
      listen = [
        {
          addr = cacheAddress;
          port = cachePort;
        }
      ];
      root = cacheDirectory;
      locations."/".extraConfig = ''
        autoindex off;
        limit_except GET {
          deny all;
        }
      '';
    };
  };

  networking.firewall.interfaces.${cacheInterface}.allowedTCPPorts = [ cachePort ];
}
