{ pkgs, ... }:

# MCP サーバーはここにだけ書く。claude.nix と agy.nix が enableMcpIntegration で読み込む
{
  programs.mcp = {
    enable = true;
    servers = {
      playwright.command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
      # SolidCraft.app は Nix の外 (手で入れたアプリ) にある
      solidcraft = {
        command = "/Applications/SolidCraft.app/Contents/MacOS/solidcraft-cli";
        args = [ "mcp" ];
      };
    };
  };
}
