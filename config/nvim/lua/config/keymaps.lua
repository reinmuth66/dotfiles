-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- インサートモードで現在時刻を <HH:MM> 形式で挿入
vim.keymap.set("i", "<C-g>t", function()
  return os.date("<%H:%M> ")
end, { expr = true, desc = "Insert current time" })
