{ ... }:

{
  programs.atuin = {
    enable = true;
    enableZshIntegration = false;
    settings = {
      enter_accept = true;
      sync.records = true;
    };
  };
}
