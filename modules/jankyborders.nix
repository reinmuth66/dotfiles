{ pkgs, ... }:

{
  services.jankyborders = {
    enable = true;

    # borders calls AXIsProcessTrusted() at startup to decide whether to enable ax_focus. We do not use ax_focus, but
    # macOS records every caller of it as a denied entry in the Accessibility permission, one for each store path.
    # Fix ax_focus to off and remove the call, so that borders never touches the permission. With ax_focus off, it
    # uses SkyLight to get the front window and needs no permission.
    package = pkgs.jankyborders.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace src/main.c \
          --replace-fail "g_settings.ax_focus = ax_check_trust(true);" "g_settings.ax_focus = false;"
      '';
    });

    settings = {
      style = "round";
      width = 4.0;
      hidpi = "on";
      active_color = "0xff9a9a9c";
      inactive_color = "0xff414550";
    };
  };
}
