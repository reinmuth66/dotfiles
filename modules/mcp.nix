{ pkgs, ... }:

# どのプロジェクトでも使う MCP サーバーだけを、ここに書く。claude.nix と agy.nix が enableMcpIntegration で読み込む。
# 特定のプロジェクトだけで使うもの (solidcraft、blender) は、そのフォルダの .mcp.json に書く (AGENTS.md を参照)
{
  programs.mcp = {
    enable = true;
    servers.playwright.command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
  };
}
