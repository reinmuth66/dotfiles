{ lib, pkgs, ... }:

# Spotify のポップアップに重ねて表示する、円形のサウンドビジュアライザ (cava の SDL 版)。
# 起動と停止、窓の位置合わせは config/sketchybar/items/spotify.lua が行う。
# .app の作り方と、音声取得の許可については pkgs/cavaviz/default.nix を参照。
let
  cavaviz = pkgs.callPackage ../pkgs/cavaviz { };

  # cava は設定ディレクトリ ($XDG_CONFIG_HOME/cava/shaders) からシェーダーを読む。
  # 同梱の orion_circle.frag は、棒の高さを隣の棒と補間して先端を傾けるので、その 1 行をやめた
  # orion_flat.frag を作る。上流で該当行が変わったら、--replace-fail でビルドが失敗する。
  # 必要なシェーダーが揃っていれば、cava は設定ディレクトリに何も書き込まない
  # (読み取り専用のストアでも動く。実機で確認済み)。
  shaders = "${pkgs.cava.src}/output/shaders";
  configHome = pkgs.runCommand "cavaviz-config-home" { } ''
    mkdir -p $out/cava/shaders
    cp ${shaders}/pass_through.vert $out/cava/shaders/pass_through.vert
    substitute ${shaders}/orion_circle.frag $out/cava/shaders/orion_flat.frag \
      --replace-fail 'float y = mix(y0, y1, f);' 'float y = y0;'
  '';

  # sdl_x / sdl_y / sdl_width / sdl_height はポップアップを開くたびに変わるので、@X@ などのまま置いておき、
  # spotify.lua が置き換えて、キャッシュに書き出したものを cava に渡す。
  settings = {
    general = {
      framerate = 30;
      bars = 24;
      # 棒の数は、窓の幅 (spotify.lua の VIZ_SIZE = 84) に収まる範囲に限られる:
      # bars × (bar_width + bar_spacing) <= 窓の幅。超えると cava が "window is too narrow" で終了する
      # (4 + 2 だと 13 本まで)。円形のシェーダーでは、bar_width / (bar_width + bar_spacing) が
      # 棒の太さの比率になる (2/3)。比率を変えなければ、大きさは小さくしてよい。
      bar_width = 2;
      bar_spacing = 1;
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
      fragment_shader = "orion_flat.frag";
      sdl_width = "@SIZE@";
      sdl_height = "@SIZE@";
      sdl_x = "@X@";
      sdl_y = "@Y@";
    };
    color = {
      background = "'#111111'";
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
