{ inputs, pkgs, ... }:

let
  terminal-browser = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.terminal-browser;
in
{
  home = {
    packages = [ terminal-browser ];

    # skill は本体と同じ版から配る (terminal-browser setup が作るリンクの代わり)
    file.".claude/skills/terminal-browser".source =
      "${terminal-browser}/share/terminal-browser/skills/default/terminal-browser";
  };
}
