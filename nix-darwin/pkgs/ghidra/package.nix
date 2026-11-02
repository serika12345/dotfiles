{
  lib,
  stdenv,
  stdenvNoCC,
  runCommand,
  ghidra-bin,
  gradle_8-unwrapped,
  xcbuild,
  makeWrapper,
  desktopToDarwinBundle,
  openjdk21,
  symlinkJoin,
}:

let
  nativePlatform = if stdenv.hostPlatform.isAarch64 then "mac_arm_64" else "mac_x86_64";

  desktopBundleHook = desktopToDarwinBundle.overrideAttrs (oldAttrs: {
    buildCommand = oldAttrs.buildCommand + ''
      substituteInPlace "$out/nix-support/setup-hook" \
        --replace-fail 'magick convert' 'magick'
    '';
  });

  # Reuse the cached release and compile only the missing macOS executables.
  natives = stdenv.mkDerivation {
    pname = "ghidra-natives";
    inherit (ghidra-bin) version;
    src = "${ghidra-bin}/lib/ghidra";
    nativeBuildInputs = [
      gradle_8-unwrapped
      xcbuild
    ];
    __darwinAllowLocalNetworking = true;
    dontConfigure = true;
    # Matching JVM options keeps Gradle in-process, avoiding daemon connections
    # rejected by Nix's strict Darwin sandbox. Native builds need no proxy.
    buildPhase = ''
      runHook preBuild
      export GRADLE_USER_HOME="$TMPDIR/gradle-home"
      export JAVA_OPTS="-Xmx2g -Xms256m -Dfile.encoding=UTF-8 -Duser.language=en -Duser.country=US -Duser.variant="
      gradle --offline --no-daemon --console=plain \
        "-Dorg.gradle.jvmargs=$JAVA_OPTS" \
        --max-workers="$NIX_BUILD_CORES" \
        -p support/gradle buildNatives
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      for module in GPL/DemanglerGnu Ghidra/Features/Decompiler Ghidra/Features/FileFormats; do
        install -Dm755 "$module"/build/os/${nativePlatform}/* -t "$out/lib/ghidra/$module/os/${nativePlatform}"
      done
      runHook postInstall
    '';
  };

  # Ghidra resolves its installation from canonical JAR paths, so copy the
  # release when adding native executables and regenerate its Java launcher.
  runtime = runCommand ghidra-bin.name { nativeBuildInputs = [ makeWrapper ]; } ''
    mkdir -p "$out"
    cp -a "${ghidra-bin}/." "$out/"
    chmod -R u+w "$out"
    cp -R "${natives}/." "$out/"
    mv "$out/lib/ghidra/support/.launch.sh-wrapped" "$out/lib/ghidra/support/launch.sh"
    wrapProgram "$out/lib/ghidra/support/launch.sh" \
      --prefix PATH : ${lib.makeBinPath [ openjdk21 ]}
  '';

  app = stdenvNoCC.mkDerivation {
    pname = "ghidra-app";
    inherit (ghidra-bin) version;
    dontUnpack = true;
    nativeBuildInputs = [
      makeWrapper
      desktopBundleHook
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/share"
      makeWrapper "${runtime}/lib/ghidra/ghidraRun" "$out/bin/ghidra"
      ln -s "${runtime}/share/applications" "$out/share/applications"
      ln -s "${runtime}/share/icons" "$out/share/icons"

      runHook postInstall
    '';

    postFixup = ''
      cp --remove-destination "$out/bin/ghidra" "$out/Applications/Ghidra.app/Contents/MacOS/Ghidra"
      rm -r "$out/bin" "$out/share"
    '';
  };
in
symlinkJoin {
  name = ghidra-bin.name;
  inherit (ghidra-bin) version meta;
  paths = [
    app
    runtime
  ];
  passthru = { inherit natives runtime; };
}
