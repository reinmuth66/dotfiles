{ catppuccin-bat, ... }:

{
  programs.bat = {
    enable = true;
    config.theme = "Catppuccin Macchiato";
    themes = {
      "Catppuccin Macchiato" = {
        src = catppuccin-bat;
        file = "themes/Catppuccin Macchiato.tmTheme";
      };
    };
  };
}
