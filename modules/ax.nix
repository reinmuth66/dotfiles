{ inputs, pkgs, ... }:

{
  home = {
    packages = [ inputs.ax.packages.${pkgs.stdenv.hostPlatform.system}.ax ];

    # skill は本体と同じタグから配り、版をそろえる (agent-skills の registry はブランチを追うので使わない)
    file.".claude/skills/ax".source = "${inputs.ax}/skills/ax";
  };
}
