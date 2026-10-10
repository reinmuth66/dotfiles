{ stdenvNoCC, cava }:

# An .app for laying cava's SDL/GLSL version under sketchybar's Spotify popup to draw the background and bar graph.
#
# - Apply sdl-window.patch to cava. Borderless, window level 100, click-through, does not steal focus.
#   The window level is below sketchybar's popup at 101, so the popup's text and images are drawn above the window.
#   It also removes cava's process of checking for permission in advance and exiting with an error if absent. See below.
# - sdl-transparent.patch: makes the window transparent. nixpkgs's SDL2 is sdl2-compat with SDL3 inside, and passes the window creation flags
#   to SDL3 as is, so add SDL3's SDL_WINDOW_TRANSPARENT, 0x40000000.
#   Without it SDL3 paints the window view's background black and the shader's alpha is ignored. It also requests a GL surface with alpha.
#   Where the shader draws with alpha 0, i.e. outside the popup's corners, the desktop behind shows through. The shader is popup.frag.
# - sdl-highdpi.patch: makes the window's drawing surface Retina resolution, 1pt = 2px. The shader draws in pt, so rounded corners, borders,
#   and a window at a half-point position can be drawn without blur. glViewport on resize also uses the size in px, not pt.
# - sdl-fractional-position.patch: accept fractions in the window position instruction "show X Y" and place it with NSWindow's setFrameOrigin.
#   SDL_SetWindowPosition can only specify integer pt, but a SketchyBar popup may be drawn at a half-point position
#   when center-aligned and the item's position is x.5, which makes the background and border drawn in the window look misaligned.
# - sdl-progress.patch: passes the playback position 0 to 1 to the shader's uniform float viz_progress. The value is written in decimal to
#   the file at $CAVAVIZ_PROGRESS, and cava reads it each frame only when the modification time has changed.
#   The control file holds only the last instruction, and writing it right after "show" would erase "show", so it is a separate file.
#   When the value changes, it redraws once even if the bars are not moving or there is silence.
#   The shader distinguishes the colors of played and unplayed bars. See popup.frag.
# - tap-gate.patch: lets the audio capture tap be switched on and off while running. When "on" or "off" is written to the file at $CAVAVIZ_AUDIO,
#   cava creates or releases the tap within 100ms. While "off" there is no tap, so
#   the system does not record audio, the recording indicator disappears, and the bars fall to 0.
#   When launched with "off", it starts without touching the hardware, with the default output device's sample rate and
#   stereo 32-bit float format. This is the same as the tap's format.
#   This is because we want to show the window that indicates the playback position by bar color even while paused, but stop recording.
# - sdl-ax-subrole.patch: sets the window's accessibility subrole to AXSystemFloatingWindow. With the default
#   AXStandardWindow, AeroSpace makes the window managed, and on exit it moves focus to the first window of the workspace.
#   In an app with multiple windows, the window being worked in switches on its own.
# - fftw-estimate.patch: changes FFT planning from FFTW_MEASURE, which measures to find the fastest method, to FFTW_ESTIMATE.
#   cava_init at startup goes from about 670ms to a few ms. The result is the same. Most of the startup slowness was here.
# - The Core Audio tap for audio capture requires the "System Audio Recording" permission. The permission attaches to the launching app,
#   so it does not pass as a child process of sketchybar. Wrap it in a dedicated .app, launch it with open, and attach the permission to the .app.
#   Since the advance check was removed, when permission is absent the standard macOS dialog appears. Pressing "Allow" lets it through from then on.
#   The first launch while the dialog is showing exits because the audio format cannot be obtained.
# - The permission is tied to the signature's "designated requirement". The default requirement of an ad-hoc signature is the cdhash, so it comes off every time cava is updated.
#   So sign with the requirement being only the identifier. The permission remains after updates. Confirmed on the actual device.
#   If the identifier is changed, the permission must be attached again. Old entries can be removed with tccutil reset AudioCapture <identifier>.
#   The permission can also be attached by manually adding CavaViz.app to "System Audio Recording Only" in System Settings.
#   Even if it does not appear in the list, it is recorded in the permission database.
# - Signing uses macOS's standard /usr/bin/codesign. Because the Nix sandbox is disabled, i.e. sandbox = false,
#   it can be used during the build. With the sandbox enabled, this build would fail.
let
  identifier = "local.dotfiles.cavaviz";

  # The patches use objc_msgSend, so link the Objective-C runtime via NIX_LDFLAGS in env.
  cavaSdl = (cava.override { withSDL2 = true; }).overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./sdl-window.patch
      ./sdl-transparent.patch
      ./fftw-estimate.patch
      ./sdl-ax-subrole.patch
      ./sdl-highdpi.patch
      ./sdl-fractional-position.patch
      ./sdl-progress.patch
      ./tap-gate.patch
    ];
    env = (old.env or { }) // {
      NIX_LDFLAGS = "-lobjc";
    };
  });
in
# Darwin's fixup re-signs Mach-O with ad-hoc and would overwrite the designated requirement attached below, so use dontFixup.
stdenvNoCC.mkDerivation {
  name = "cavaviz";

  dontUnpack = true;
  dontFixup = true;

  installPhase = ''
    app=$out/Applications/CavaViz.app
    mkdir -p $app/Contents/MacOS
    cp ${cavaSdl}/bin/cava $app/Contents/MacOS/cava
    cat > $app/Contents/Info.plist <<'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>${identifier}</string>
    <key>CFBundleName</key><string>CavaViz</string>
    <key>CFBundleExecutable</key><string>cava</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>NSAudioCaptureUsageDescription</key><string>Spotify visualizer for sketchybar</string>
    </dict></plist>
    PLIST
    /usr/bin/codesign --force --sign - -r='designated => identifier "${identifier}"' $app
  '';
}
