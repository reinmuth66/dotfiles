{ stdenv, target }:

# A minimal .app that launchd starts in place of a wrapper script, so that a macOS permission
# (Accessibility, Screen Recording, ...) stays attached across Nix store path changes.
# Copy this directory to pkgs/<tool>-app/ and replace <tool> (lowercase name) and <Tool> (.app display name).
#
# - The kernel makes the first non-Apple executable that launchd's /bin/sh execs the "responsible process" for the whole tree.
#   If it is not the main executable of an .app, TCC records the permission by path, and a Nix store path changes on every update.
#   A shell-script wrapper makes the store's bash the responsible process, so the permission comes off on every nixpkgs update.
# - So put a tiny launcher (main.c) in an .app and let launchd start it. It becomes the responsible process, and because it is
#   the main executable of the .app, TCC attributes it to the bundle identifier. The launcher then execs target, the unchanged
#   wrapper, so the wrapper's environment (PATH etc.) need not be reproduced.
# - The permission is tied to the signature's "designated requirement". The default requirement of an ad-hoc signature is the
#   cdhash, so sign with the requirement being only the identifier. If the identifier is changed, the permission must be attached again.
# - Darwin's fixup re-signs Mach-O and would overwrite the designated requirement, so use dontFixup.
#   Signing uses macOS's standard /usr/bin/codesign, which works only because the Nix sandbox is disabled (sandbox = false).
let
  identifier = "local.dotfiles.<tool>";
in
stdenv.mkDerivation {
  name = "<tool>-app";

  dontUnpack = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Werror -DTARGET='"${target}"' ${./main.c} -o <tool>-launcher
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    app=$out/Applications/<Tool>.app
    mkdir -p $app/Contents/MacOS
    cp <tool>-launcher $app/Contents/MacOS/<tool>-launcher
    cat > $app/Contents/Info.plist <<'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>${identifier}</string>
    <key>CFBundleName</key><string><Tool></string>
    <key>CFBundleExecutable</key><string><tool>-launcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    </dict></plist>
    PLIST
    /usr/bin/codesign --force --sign - -r='designated => identifier "${identifier}"' $app
    runHook postInstall
  '';
}
