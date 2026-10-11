{ stdenv, target }:

# A minimal .app that launchd starts in place of the sketchybar wrapper. It makes the Accessibility permission
# stay attached across updates.
#
# - Why the permission came off: the sketchybar from programs.sketchybar is a bash script that sets PATH and so on and then execs the real binary.
#   The kernel makes the first non-Apple executable that launchd's /bin/sh execs the "responsible process" for the whole tree, and
#   TCC attaches permission to it by path. That was the Nix store's bash, so the permission came off
#   every time bash's store path changed, i.e. on every nixpkgs update. The children osascript and media-key are attributed to it.
# - So put a tiny launcher (main.c) in an .app and let launchd start it. Because it is the first non-Apple executable,
#   it becomes the responsible process, and because it is the main executable of the .app, TCC attributes it to the bundle identifier.
#   The launcher then execs target, the unchanged sketchybar wrapper, so PATH and LUA_PATH need not be reproduced.
#   Once a process becomes responsible, a later exec does not change it. Confirmed on the actual device.
# - The permission is tied to the signature's "designated requirement". The default requirement of an ad-hoc signature is the cdhash,
#   so sign with the requirement being only the identifier. Same as pkgs/cavaviz.
#   If the identifier is changed, the permission must be attached again.
#   The permission can also be attached by manually adding Sketchybar.app to "Accessibility" in System Settings.
# - Darwin's fixup re-signs Mach-O and would overwrite the designated requirement, so use dontFixup.
#   Signing uses macOS's standard /usr/bin/codesign. It works because sandbox = false, same as pkgs/cavaviz.
let
  identifier = "local.dotfiles.sketchybar";
in
stdenv.mkDerivation {
  name = "sketchybar-app";

  dontUnpack = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Werror -DTARGET='"${target}"' ${./main.c} -o sketchybar-launcher
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    app=$out/Applications/Sketchybar.app
    mkdir -p $app/Contents/MacOS
    cp sketchybar-launcher $app/Contents/MacOS/sketchybar-launcher
    cat > $app/Contents/Info.plist <<'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>${identifier}</string>
    <key>CFBundleName</key><string>Sketchybar</string>
    <key>CFBundleExecutable</key><string>sketchybar-launcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    </dict></plist>
    PLIST
    /usr/bin/codesign --force --sign - -r='designated => identifier "${identifier}"' $app
    runHook postInstall
  '';
}
