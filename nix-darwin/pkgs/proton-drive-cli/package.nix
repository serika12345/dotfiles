{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "proton-drive-cli";
  version = "0.6.0";

  src = fetchurl {
    url = "https://proton.me/download/drive/cli/${finalAttrs.version}/darwin-arm64/proton-drive";
    hash = "sha512-dEqFRAOg9XMOx8VdPIuthKsXlZC3vnf8bBOPYbD5homsYnYSUgNzU7JkOl0a0bUt7EaujChTzvsqf9Gl4gFsWQ==";
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/bin/proton-drive"

    runHook postInstall
  '';

  meta = {
    description = "Official command-line client for Proton Drive";
    homepage = "https://proton.me/support/drive-cli";
    license = lib.licenses.unfree;
    mainProgram = "proton-drive";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
