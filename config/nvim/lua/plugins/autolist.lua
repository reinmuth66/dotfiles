return {
  "gaoDean/autolist.nvim",
  ft = "markdown",
  opts = {},
  keys = {
    { "<CR>", "<CR><cmd>AutolistNewBullet<cr>", mode = "i", ft = "markdown" },
    { "o", "o<cmd>AutolistNewBullet<cr>", mode = "n", ft = "markdown" },
    { "O", "O<cmd>AutolistNewBulletBefore<cr>", mode = "n", ft = "markdown" },
  },
}
