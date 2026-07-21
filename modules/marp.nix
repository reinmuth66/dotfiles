{ ... }:

{
  xdg.configFile = {
    "marp/simple-theme.css".source = ../config/marp/simple-theme.css;
    "marp/new-theme.css".source = ../config/marp/new-theme.css;
    "marp/.marprc.yml".source = ../config/marp/.marprc.yml;
  };

  home.file.".marprc.yml".source = ../config/marp/.marprc.yml;
}
