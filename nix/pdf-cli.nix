{ lib, buildGoModule, src }:

buildGoModule rec {
  pname = "pdf-cli";
  version = "unstable-${builtins.substring 0 4 src.lastModifiedDate}-${builtins.substring 4 2 src.lastModifiedDate}-${builtins.substring 6 2 src.lastModifiedDate}";

  inherit src;

  # Depends on go.sum, so it is not tracked by the flake input. update-flake.yaml recomputes it.
  vendorHash = "sha256-LCIv135ywuq494hZbrKdbqkGPSsSlSkVQ9hCE8i7www=";

  patches = [ ./pdf-cli-wezterm-kitty.patch ];
  patchFlags = [ "-p1" ];

  env.CGO_ENABLED = "1";

  postInstall = ''
    ln -s $out/bin/pdf-cli $out/bin/dvctl
  '';

  meta = {
    description = "Terminal-based PDF/EPUB viewer with image protocol rendering";
    homepage = "https://github.com/Yujonpradhananga/pdf-cli";
    mainProgram = "pdf-cli";
    platforms = lib.platforms.darwin ++ lib.platforms.linux;
  };
}
