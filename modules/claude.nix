{ ... }:

{
  home.file = {
    ".claude/CLAUDE.md".source = ../config/claude/CLAUDE.md;
    ".claude/statusline.sh" = {
      source = ../config/claude/statusline.sh;
      executable = true;
    };
  };
}
