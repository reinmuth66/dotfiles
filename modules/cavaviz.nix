{ lib, pkgs, ... }:

# Spotify のポップアップの再生位置バーに重ねて表示する、棒グラフのサウンドビジュアライザ (cava の SDL 版)。
# 起動と停止、窓の位置合わせは config/sketchybar/items/spotify.lua が行う。
# .app の作り方と、音声取得の許可については pkgs/cavaviz/default.nix を参照。
let
  cavaviz = pkgs.callPackage ../pkgs/cavaviz { };

  # cava は設定ディレクトリ ($XDG_CONFIG_HOME/cava/shaders) からシェーダーを読む。
  # 同梱の bar_spectrum.frag を、次の 3 点だけ変えた bar_clear.frag にして使う。
  # - 背景 (棒の外と、棒の間の隙間) を、bg_color ではなくアルファ 0 (透明) で描く (窓の透明化は sdl-transparent.patch)。
  # - 無音のときに底に引く 1px の線をやめる (棒の高さが 1px 未満なら 0 にする)。
  # - 棒を半透明 (アルファ 0.5) にして、重なる文字を透けて見せる。窓は premultiplied alpha で合成されるので、色にもアルファを掛ける。
  # 上流で該当の行が変わったら、--replace-fail でビルドが失敗する。
  # 必要なシェーダーが揃っていれば、cava は設定ディレクトリに何も書き込まない
  # (読み取り専用のストアでも動く。実機で確認済み)。
  shaders = "${pkgs.cava.src}/output/shaders";
  configHome = pkgs.runCommand "cavaviz-config-home" { } ''
    mkdir -p $out/cava/shaders
    cp ${shaders}/pass_through.vert $out/cava/shaders/pass_through.vert
    substitute ${shaders}/bar_spectrum.frag $out/cava/shaders/bar_clear.frag \
      --replace-fail 'fragColor = vec4(bg_color, 1.0);' 'fragColor = vec4(0.0);' \
      --replace-fail 'y = 1.0 / u_resolution.y;' 'y = 0.0;' \
      --replace-fail 'fragColor = vec4(fg_color, 1.0);' 'fragColor = vec4(fg_color * 0.5, 0.5);'
  '';

  # sdl_x / sdl_y はポップアップを開くたびに変わるので、@X@ などのまま置いておき (幅と高さも @W@ @H@ にして、
  # 大きさは spotify.lua の VIZ_WIDTH / VIZ_HEIGHT に合わせる)、
  # spotify.lua が置き換えて、キャッシュに書き出したものを cava に渡す。
  settings = {
    general = {
      framerate = 30;
      bars = 40;
      # 棒の数は、窓の幅 (spotify.lua の VIZ_WIDTH = 200) に収まる範囲に限られる:
      # bars × bar_width + (bars - 1) × bar_spacing <= 窓の幅。超えると cava が "window is too narrow" で終了する。
      # bar_spacing は、bar_clear.frag (bar_spectrum.frag と同じ) では棒と棒の間の隙間 (px) になる (棒の幅は窓の幅 / bars - bar_spacing)。
      bar_width = 3;
      bar_spacing = 2;
      # 固定の感度にする。autosens は起動直後に感度を 0 から上げるので、棒が約 0.8 秒かけて伸びてしまう。
      # 感度は、Spotify の再生音で、最大の棒の 99 パーセンタイルが 0.9 になる値 (曲や音量で変わる)。
      autosens = 0;
      sensitivity = 4300;
    };
    input = {
      method = "coreaudio";
      source = "tap"; # 再生中の音 (システム全体のミックス)
    };
    output = {
      method = "sdl_glsl";
      vertex_shader = "pass_through.vert";
      fragment_shader = "bar_clear.frag";
      # mono は、左から右へ低音から高音の順に並べる (stereo だと、低音が左右の端、高音が中央の鏡像になる)
      channels = "mono";
      mono_option = "average";
      sdl_width = "@W@";
      sdl_height = "@H@";
      sdl_x = "@X@";
      sdl_y = "@Y@";
    };
    color = {
      background = "'#111111'"; # bar_clear.frag では使わない (窓は透明)
      foreground = "'#33ffff'";
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
