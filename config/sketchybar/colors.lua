return {
  white = 0xffffffff,

  space = {
    bg = 0x44ffffff,
    bg_focused = 0x88ff00ff,
    border = 0xaaffffff,
  },

  -- ui.add_bracket の既定の背景
  bracket = {
    color = 0x66000000,
    border_color = 0x44ffffff,
    border_width = 1,
    corner_radius = 5,
    height = 30,
  },

  -- ポップアップの背景。壁紙に文字が埋もれないよう bracket より濃くする
  popup = {
    color = 0xcc000000,
    border_color = 0x44ffffff,
    border_width = 1,
    corner_radius = 5,
  },

  swap = {
    default = 0x44ffffff,
    alert = 0xaaff0000,
  },
}
