return {
  white = 0xffffffff,

  -- workspace は背景を持たず、フォーカス中だけ文字色を変えて示す
  space = {
    fg = 0xffffffff,
    fg_focused = 0xffff66ff,
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
