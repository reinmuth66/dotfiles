{ ... }:

{
  home.file = {
    ".claude/CLAUDE.md".source = ../config/claude/CLAUDE.md;
    ".claude/statusline.sh" = {
      source = ../config/claude/statusline.sh;
      executable = true;
    };
    ".claude/commands".source = ../config/claude/commands;
    ".claude/agents".source = ../config/claude/agents;
  };
}
