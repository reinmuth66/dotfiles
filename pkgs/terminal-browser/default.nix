{ stdenvNoCC, fetchurl }:

stdenvNoCC.mkDerivation rec {
  pname = "terminal-browser";
  version = "0.16.3";

  src = fetchurl {
    url = "https://terminal-browser.sh/install/dl/stable/v${version}/terminal-browser-darwin-arm64.tar.gz";
    hash = "sha256-QuiUpBH1TKmlUjf2xlTJx6kPRZZv901NmzauDWCNvoc=";
  };

  # 配布物は Electron と署名済みの補助の実行ファイルを含む。修正しない (strip などで署名を壊さない)
  dontFixup = true;

  # bin/terminal-browser はリンクをたどって自分の置き場所を求めるので、一式を share に置いてリンクを張る
  installPhase = ''
    runHook preInstall
    # tarball に macOS の拡張属性 (._*) が入っていて、GNU tar はふつうのファイルとして出す。署名の外のファイルになり、起動が止められるので消す
    find . -name '._*' -delete
    mkdir -p $out/share/terminal-browser $out/bin
    cp -R . $out/share/terminal-browser/
    ln -s $out/share/terminal-browser/bin/terminal-browser $out/bin/terminal-browser
    runHook postInstall
  '';

  meta = {
    description = "A real browser running inside the terminal";
    mainProgram = "terminal-browser";
    platforms = [ "aarch64-darwin" ];
  };
}
