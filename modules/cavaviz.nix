{ lib, pkgs, ... }:

# Spotify のポップアップの下に敷く、棒グラフのサウンドビジュアライザ。cava の SDL 版を使う。
# cava の窓は、ポップアップの背景、枠、棒グラフを描く。SketchyBar のポップアップ自身の背景は透明にして、
# 文字やカバー画像、再生位置のバーだけを、この窓の上に描かせる。
# 別の窓の前後は window level でしか決まらず、1 つの窓の中の背景と文字の間には入れないため。
# 起動と停止、窓の位置合わせ、背景の受け渡しは config/sketchybar/items/spotify.lua が行う。
# .app の作り方と、音声取得の許可については pkgs/cavaviz/default.nix を参照。
let
  cavaviz = pkgs.callPackage ../pkgs/cavaviz { };

  # 必要なシェーダーが揃っていれば、cava は設定ディレクトリに何も書き込まない。
  # 読み取り専用のストアでも動くことを、実機で確認済み。
  shaders = "${pkgs.cava.src}/output/shaders";

  # 窓の大きさの sdl_width と sdl_height は、spotify.lua の POPUP_PADDING、TEXT_WIDTH、POPUP_BORDER、
  # POPUP_HEIGHT から決まる。二重に持たないよう、ここには書かない。
  #
  # general の bar_width と bar_spacing:
  #   棒は、棒を描く領域の両端に、最初の棒の左端と最後の棒の右端が合うように並ぶ。
  #   領域の幅は popup.frag の VIZ の幅で、spotify.lua の TEXT_WIDTH の 222。
  #   棒の幅は (領域の幅 - (bars - 1) × bar_spacing) / bars になる。bar_width は使われない。
  #   cava は、bars × bar_width + (bars - 1) × bar_spacing が窓の幅を超えると、
  #   "window is too narrow" で終了する。窓の幅はポップアップの幅。
  # general の autosens と sensitivity:
  #   固定の感度にする。autosens は起動直後に感度を 0 から上げるので、棒が約 0.8 秒かけて伸びてしまう。
  #   感度は、Spotify の再生音で、最大の棒の 99 パーセンタイルが 0.9 になる値。曲や音量で変わる。
  # output の channels:
  #   mono は、左から右へ低音から高音の順に並べる。stereo だと、低音が左右の端、高音が中央の鏡像になる。
  # color の gradient:
  #   foreground と background ではなくグラデーションで指定するのは、SIGUSR2 で読み直されるのが、
  #   グラデーションの色だけだから。グラデーションの有無と色数も読み直される。foreground と background は読み直されない。
  # smoothing の noise_reduction:
  #   10 以下は、音が切れたときの落下の緩和が無効になり、棒が瞬時に落ちる。
  settings = {
    general = {
      framerate = 30;
      bars = 32;
      lower_cutoff_freq = 40;
      higher_cutoff_freq = 12000;
      bar_width = 3;
      bar_spacing = 2;
      autosens = 0;
      sensitivity = 3500;
    };
    input = {
      method = "coreaudio";
      source = "tap"; # 再生中の音。システム全体のミックス
    };
    output = {
      method = "sdl_glsl";
      vertex_shader = "pass_through.vert";
      fragment_shader = "popup.frag";
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
      gradient = 1;
      gradient_color_1 = "'@FG@'";
      gradient_color_2 = "'@BG@'";
      gradient_color_3 = "'@BORDER@'";
      gradient_color_4 = "'@PLAYED@'";
    };
    smoothing = {
      noise_reduction = 10;
    };
  };
in
{
  home.packages = [ cavaviz ];

  xdg.configFile."cavaviz/cava/shaders/pass_through.vert".source = "${shaders}/pass_through.vert";
  xdg.configFile."cavaviz/cava/shaders/popup.frag".source = ../pkgs/cavaviz/popup.frag;
  xdg.configFile."cavaviz/config.template".text = lib.generators.toINI { } settings;
}
