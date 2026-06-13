-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- インサートモードで現在時刻を <HH:MM> 形式で挿入
vim.keymap.set("i", "<C-l>", function()
  local time = tostring(os.date("<%H:%M> "))
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, { time })
  vim.api.nvim_win_set_cursor(0, { row, col + #time })
end, { desc = "Insert current time" })
