{ lib, pkgs, ... }:

# A bar-graph sound visualizer laid under the Spotify popup. Uses the SDL version of cava.
# The cava window draws the popup's background, border, and bar graph. The SketchyBar popup's own background is made transparent,
# so that only the text, cover image, and playback position bar are drawn on top of this window.
# Ordering between separate windows is decided only by window level, and nothing can be inserted between the background and text inside a single window.
# Launching and stopping, aligning the window position, and handing over the background are done by config/sketchybar/items/spotify.lua.
# For how the .app is built and the audio capture permission, see pkgs/cavaviz/default.nix.
let
  cavaviz = pkgs.callPackage ../pkgs/cavaviz { };

  # If the required shaders are present, cava writes nothing to the config directory.
  # Confirmed on the actual device that it works even with a read-only store.
  shaders = "${pkgs.cava.src}/output/shaders";

  # The window size's sdl_width and sdl_height are determined by POPUP_PADDING, TEXT_WIDTH, POPUP_BORDER, and
  # POPUP_HEIGHT in spotify.lua. They are not written here, to avoid keeping them in two places.
  #
  # bar_width and bar_spacing in general:
  #   Bars are laid out so that the first bar's left edge and the last bar's right edge meet the two ends of the area where bars are drawn.
  #   The area width is the width of VIZ in popup.frag, which is 222 as TEXT_WIDTH in spotify.lua.
  #   The bar width is (area width - (bars - 1) × bar_spacing) / bars. bar_width is not used.
  #   cava exits with "window is too narrow" if bars × bar_width + (bars - 1) × bar_spacing exceeds the window width.
  #   The window width is the popup width.
  # autosens and sensitivity in general:
  #   Use a fixed sensitivity. autosens raises sensitivity from 0 right after startup, so the bars would take about 0.8 seconds to grow.
  #   The sensitivity is the value at which the 99th percentile of the largest bar is 0.9 with Spotify playback. It varies with track and volume.
  # channels in output:
  #   mono lays out bass to treble from left to right. With stereo it would be a mirror image, with bass at the left and right ends and treble in the center.
  # gradient in color:
  #   The reason for specifying by gradient instead of foreground and background is that only the gradient colors are re-read on SIGUSR2.
  #   Whether a gradient is present and the number of colors are also re-read. foreground and background are not re-read.
  # noise_reduction in smoothing:
  #   At 10 or below, the fall-off easing when sound cuts out is disabled and the bars drop instantly.
  settings = {
    general = {
      framerate = 30;
      bars = 32;
      lower_cutoff_freq = 40;
      higher_cutoff_freq = 12000;
      bar_width = 3;
      bar_spacing = 2;
      autosens = 0;
      sensitivity = 3500;
    };
    input = {
      method = "coreaudio";
      source = "tap"; # the audio being played. The system-wide mix
    };
    output = {
      method = "sdl_glsl";
      vertex_shader = "pass_through.vert";
      fragment_shader = "popup.frag";
      channels = "mono";
      mono_option = "average";
      sdl_width = "@W@";
      sdl_height = "@H@";
      sdl_x = "@X@";
      sdl_y = "@Y@";
    };
    color = {
      background = "'#111111'"; # not used in popup.frag
      foreground = "'#ffffff'"; # same as above
      gradient = 1;
      gradient_color_1 = "'@FG@'";
      gradient_color_2 = "'@BG@'";
      gradient_color_3 = "'@BORDER@'";
      gradient_color_4 = "'@PLAYED@'";
    };
    smoothing = {
      noise_reduction = 10;
    };
  };
in
{
  home.packages = [ cavaviz ];

  xdg.configFile."cavaviz/cava/shaders/pass_through.vert".source = "${shaders}/pass_through.vert";
  xdg.configFile."cavaviz/cava/shaders/popup.frag".source = ../pkgs/cavaviz/popup.frag;
  xdg.configFile."cavaviz/config.template".text = lib.generators.toINI { } settings;
}
