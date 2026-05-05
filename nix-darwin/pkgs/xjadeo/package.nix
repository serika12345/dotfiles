{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "xjadeo";
  version = "0.8.15";

  src = fetchurl {
    name = "jadeo-arm64-${finalAttrs.version}.dmg";
    url = "mirror://sourceforge/project/xjadeo/xjadeo/v${finalAttrs.version}/jadeo-arm64-${finalAttrs.version}.dmg";
    hash = "sha256-iS/GjrrCBez7LembngSECGBjYev6Zz7j5Lxf9R0/Dhw=";
  };

  sourceRoot = ".";
  nativeBuildInputs = [ undmg ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    mv Jadeo.app "$out/Applications/"
    ln -s "$out/Applications/Jadeo.app/Contents/MacOS/Jadeo" "$out/bin/xjadeo"
    ln -s "$out/Applications/Jadeo.app/Contents/MacOS/xjremote" "$out/bin/xjremote"

    runHook postInstall
  '';

  meta = {
    description = "X Jack Video Monitor";
    longDescription = ''
      Xjadeo is a software video player that displays a video clip in sync with
      an external time source (MTC, LTC, JACK-transport).
    '';
    homepage = "https://xjadeo.sourceforge.net/";
    license = lib.licenses.gpl2Plus;
    mainProgram = "xjadeo";
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
