{ inputs, ... }:

{
  perSystem =
    { pkgs, ... }:
    {
      # `nix run .#skills-sources-lock` で config/agent-skills/registry の skill の取得元をまとめて更新する
      apps.skills-sources-lock = {
        type = "app";
        program = "${
          inputs.agent-skills.lib.agent-skills.mkSourceLockProgram { inherit pkgs; }
        }/bin/skills-sources-lock";
        meta.description = "Update the pinned agent skill sources";
      };
    };
}
