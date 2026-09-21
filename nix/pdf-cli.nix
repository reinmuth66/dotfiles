{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "pdf-cli";
  version = "unstable-2026-08-26";

  src = fetchFromGitHub {
    owner = "Yujonpradhananga";
    repo = "pdf-cli";
    rev = "35c904dd9842c19558050b66d611d4045050c6d9";
    hash = "sha256-9FitpNl42lccoe3OHhFJ8yOr7G2hXJXFX24F7IM2pKE=";
  };

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
