{ lib, pkgs, ... }:

# Spotify のポップアップの下に敷く、棒グラフのサウンドビジュアライザ (cava の SDL 版)。
# cava の窓は、ポップアップの背景、枠、棒グラフを描く。SketchyBar のポップアップ自身の背景は透明にして、
# 文字やカバー画像、再生位置のバーだけを、この窓の上に描かせる (別の窓の前後は window level でしか決まらず、
# 1 つの窓の中の背景と文字の間には入れないため)。
# 起動と停止、窓の位置合わせ、背景の受け渡しは config/sketchybar/items/spotify.lua が行う。
# ポップアップはバーの高さの中に収まる横長 (233 x 34 pt)。棒の幅は、領域の幅と棒の数 (bars) で決まる。
# .app の作り方と、音声取得の許可については pkgs/cavaviz/default.nix を参照。
let
  cavaviz = pkgs.callPackage ../pkgs/cavaviz { };

  # cava は設定ディレクトリ ($XDG_CONFIG_HOME/cava/shaders) からシェーダーを読む。
  # 背景、枠、棒を描く popup.frag (pkgs/cavaviz/) を置く。窓の透明化は sdl-transparent.patch。
  # 必要なシェーダーが揃っていれば、cava は設定ディレクトリに何も書き込まない
  # (読み取り専用のストアでも動く。実機で確認済み)。
  shaders = "${pkgs.cava.src}/output/shaders";
  configHome = pkgs.runCommand "cavaviz-config-home" { } ''
    mkdir -p $out/cava/shaders
    cp ${shaders}/pass_through.vert $out/cava/shaders/pass_through.vert
    cp ${../pkgs/cavaviz/popup.frag} $out/cava/shaders/popup.frag
  '';

  # sdl_x / sdl_y はポップアップを開くたびに変わるので、@X@ などのまま置いておき (幅と高さも @W@ @H@ にして、
  # 大きさは spotify.lua の POPUP_BG_WIDTH / POPUP_BG_HEIGHT に合わせる)、
  # spotify.lua が置き換えて、キャッシュに書き出したものを cava に渡す。
  settings = {
    general = {
      framerate = 30;
      bars = 32;
      lower_cutoff_freq = 40;
      higher_cutoff_freq = 12000;
      # 棒は、棒を描く領域の幅 (popup.frag の VIZ の幅 = spotify.lua の VIZ_WIDTH = 220) の両端に、最初の棒の左端と
      # 最後の棒の右端が合うように並ぶ。棒の幅は (領域の幅 - (bars - 1) × bar_spacing) / bars になる (bar_width は使われない)。
      # cava は、bars × bar_width + (bars - 1) × bar_spacing が窓の幅 (ポップアップの幅) を超えると、
      # "window is too narrow" で終了する。
      bar_width = 3;
      bar_spacing = 2;
      # 固定の感度にする。autosens は起動直後に感度を 0 から上げるので、棒が約 0.8 秒かけて伸びてしまう。
      # 感度は、Spotify の再生音で、最大の棒の 99 パーセンタイルが 0.9 になる値 (曲や音量で変わる)。
      autosens = 0;
      sensitivity = 3000;
    };
    input = {
      method = "coreaudio";
      source = "tap"; # 再生中の音 (システム全体のミックス)
    };
    output = {
      method = "sdl_glsl";
      vertex_shader = "pass_through.vert";
      fragment_shader = "popup.frag";
      # mono は、左から右へ低音から高音の順に並べる (stereo だと、低音が左右の端、高音が中央の鏡像になる)
      channels = "mono";
      mono_option = "average";
      sdl_width = "@W@";
      sdl_height = "@H@";
      sdl_x = "@X@";
      sdl_y = "@Y@";
    };
    color = {
      background = "'#111111'"; # popup.frag では使わない
      foreground = "'#ffffff'"; # 同上
      # popup.frag は、色をグラデーションの 4 色で受け取る。@FG@ (未再生の棒)、@BG@ (ポップアップの背景)、@BORDER@ (枠)、
      # @PLAYED@ (再生済みの棒) は、spotify.lua が、アルバム画像から決めた配色に置き換える。
      # foreground / background ではなくグラデーションで指定するのは、SIGUSR2 で読み直されるのが、
      # グラデーションの色 (有無と色数も) だけで、foreground / background は読み直されないため。
      # 動いている間の変更は、設定を書き直して cava に SIGUSR2 を送る (窓も音声の取得も作り直さない)。
      gradient = 1;
      gradient_color_1 = "'@FG@'";
      gradient_color_2 = "'@BG@'";
      gradient_color_3 = "'@BORDER@'";
      gradient_color_4 = "'@PLAYED@'";
    };
    smoothing = {
      # 10 以下は、音が切れたときの落下の緩和が無効になり、棒が瞬時に落ちる
      noise_reduction = 10;
    };
  };
in
{
  home.packages = [ cavaviz ];

  xdg.configFile."cavaviz/cava".source = "${configHome}/cava";
  xdg.configFile."cavaviz/config.template".text = lib.generators.toINI { } settings;
}
