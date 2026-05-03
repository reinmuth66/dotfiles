{ ... }:

{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      format = "$os$username$directory$git_branch$git_status$c$cpp$elixir$elm$golang$gradle$haskell$java$julia$kotlin$nim$nodejs$php$python$rust$scala$conda$docker_context$nix_shell$time$cmd_duration$line_break$character";
      palette = "catppuccin_mocha";
      command_timeout = 5000;

      os = {
        disabled = true;
        style = "fg:red";
        format = "[ $symbol]($style)";
        symbols = {
          Windows          = "";
          Ubuntu           = "󰕈";
          SUSE             = "";
          Raspbian         = "󰐿";
          Mint             = "󰣭";
          Macos            = "󰀵";
          Manjaro          = "";
          Linux            = "󰌽";
          Gentoo           = "󰣨";
          Fedora           = "󰣛";
          Alpine           = "";
          Amazon           = "";
          Android          = "";
          AOSC             = "";
          Arch             = "󰣇";
          Artix            = "󰣇";
          CentOS           = "";
          Debian           = "󰣚";
          Redhat           = "󱄛";
          RedHatEnterprise = "󱄛";
        };
      };

      username = {
        disabled = true;
        show_always = true;
        style_user = "bold fg:red";
        style_root = "bold fg:red";
        format = "[ $user]($style)";
      };

      directory = {
        style = "bold fg:mauve";
        format = "[ $path ]($style)";
        truncation_length = 3;
        truncation_symbol = "…/";
      };

      git_branch = {
        symbol = "";
        style = "bold fg:sky";
        format = "[$symbol $branch]($style)";
      };

      git_status = {
        deleted   = " 󱘹 $count";
        modified  = " 󰏫 $count";
        staged    = " 󱇬 $count";
        untracked = " 󰈉 $count";
        style = "bold fg:sky";
        format = "[$ahead_behind$all_status ]($style)";
      };

      bun     = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      c       = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      cpp     = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      elixir  = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      elm     = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      golang  = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      gradle  = {               style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      haskell = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      java    = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      julia   = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      kotlin  = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      nim     = { symbol = "󰆥"; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      nodejs  = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      php     = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      rust    = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };
      scala   = { symbol = ""; style = "bold fg:green"; format = "[$symbol( $version) ]($style)"; };

      python = {
        symbol = "";
        style = "bold fg:green";
        format = ''[$symbol( $version)(\(#$virtualenv\)) ]($style)'';
      };

      conda = {
        symbol = "";
        style = "bold fg:flamingo";
        format = "[$symbol $environment ]($style)";
        ignore_base = false;
      };

      docker_context = {
        symbol = "";
        style = "bold fg:flamingo";
        format = "[$symbol( $context)]($style)";
      };

      nix_shell = {
        symbol = "󱄅";
        style = "bold fg:blue";
        format = "[$symbol $state( \\($name\\)) ]($style)";
        impure_msg = "impure";
        pure_msg = "pure";
      };

      time = {
        disabled = true;
        time_format = "%R";
        style = "bg:lavender";
        format = "[[   $time ](fg:crust bg:lavender)]($style)";
      };

      line_break.disabled = false;

      character = {
        disabled = false;
        success_symbol = "[](fg:white)";
        error_symbol   = "[](fg:white)";
        vimcmd_symbol             = "[❮](bold fg:green)";
        vimcmd_replace_one_symbol = "[❮](bold fg:lavender)";
        vimcmd_replace_symbol     = "[❮](bold fg:lavender)";
        vimcmd_visual_symbol      = "[❮](bold fg:yellow)";
      };

      cmd_duration = {
        show_milliseconds = true;
        format = " in $duration ";
        style = "bg:lavender";
        disabled = true;
        show_notifications = true;
        min_time_to_notify = 45000;
      };

      palettes = {
        catppuccin_mocha = {
          rosewater = "#f5e0dc"; flamingo = "#f2cdcd"; pink = "#f5c2e7";
          mauve = "#cba6f7";     red = "#f38ba8";      maroon = "#eba0ac";
          peach = "#fab387";     yellow = "#f9e2af";   green = "#a6e3a1";
          teal = "#94e2d5";      sky = "#89dceb";      sapphire = "#74c7ec";
          blue = "#89b4fa";      lavender = "#b4befe"; text = "#cdd6f4";
          subtext1 = "#bac2de";  subtext0 = "#a6adc8"; overlay2 = "#9399b2";
          overlay1 = "#7f849c";  overlay0 = "#6c7086"; surface2 = "#585b70";
          surface1 = "#45475a";  surface0 = "#313244"; base = "#1e1e2e";
          mantle = "#181825";    crust = "#11111b";    white = "#d4e7ff";
        };
        catppuccin_frappe = {
          rosewater = "#f2d5cf"; flamingo = "#eebebe"; pink = "#f4b8e4";
          mauve = "#ca9ee6";     red = "#e78284";      maroon = "#ea999c";
          peach = "#ef9f76";     yellow = "#e5c890";   green = "#a6d189";
          teal = "#81c8be";      sky = "#99d1db";      sapphire = "#85c1dc";
          blue = "#8caaee";      lavender = "#babbf1"; text = "#c6d0f5";
          subtext1 = "#b5bfe2";  subtext0 = "#a5adce"; overlay2 = "#949cbb";
          overlay1 = "#838ba7";  overlay0 = "#737994"; surface2 = "#626880";
          surface1 = "#51576d";  surface0 = "#414559"; base = "#303446";
          mantle = "#292c3c";    crust = "#232634";
        };
        catppuccin_latte = {
          rosewater = "#dc8a78"; flamingo = "#dd7878"; pink = "#ea76cb";
          mauve = "#8839ef";     red = "#d20f39";      maroon = "#e64553";
          peach = "#fe640b";     yellow = "#df8e1d";   green = "#40a02b";
          teal = "#179299";      sky = "#04a5e5";      sapphire = "#209fb5";
          blue = "#1e66f5";      lavender = "#7287fd"; text = "#4c4f69";
          subtext1 = "#5c5f77";  subtext0 = "#6c6f85"; overlay2 = "#7c7f93";
          overlay1 = "#8c8fa1";  overlay0 = "#9ca0b0"; surface2 = "#acb0be";
          surface1 = "#bcc0cc";  surface0 = "#ccd0da"; base = "#eff1f5";
          mantle = "#e6e9ef";    crust = "#dce0e8";
        };
        catppuccin_macchiato = {
          rosewater = "#f4dbd6"; flamingo = "#f0c6c6"; pink = "#f5bde6";
          mauve = "#c6a0f6";     red = "#ed8796";      maroon = "#ee99a0";
          peach = "#f5a97f";     yellow = "#eed49f";   green = "#a6da95";
          teal = "#8bd5ca";      sky = "#91d7e3";      sapphire = "#7dc4e4";
          blue = "#8aadf4";      lavender = "#b7bdf8"; text = "#cad3f5";
          subtext1 = "#b8c0e0";  subtext0 = "#a5adcb"; overlay2 = "#939ab7";
          overlay1 = "#8087a2";  overlay0 = "#6e738d"; surface2 = "#5b6078";
          surface1 = "#494d64";  surface0 = "#363a4f"; base = "#24273a";
          mantle = "#1e2030";    crust = "#181926";
        };
      };
    };
  };
}
