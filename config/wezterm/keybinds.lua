local wezterm = require("wezterm")
local act = wezterm.action

wezterm.on("update-right-status", function(window, pane)
	local name = window:active_key_table()
	if name then
		window:set_right_status(wezterm.format({
			{ Attribute = { Intensity = "Bold" } },
			{ Text = " " .. name .. " " },
		}))
	else
		window:set_right_status("")
	end
end)

return {
	keys = {
		{
			-- workspaceの切り替え
			key = "g",
			mods = "SHIFT|CTRL",
			action = act.ShowLauncherArgs({ flags = "WORKSPACES", title = "Select workspace" }),
		},
		{
			--workspaceの名前変更
			key = "t",
			mods = "SHIFT|CTRL",
			action = act.PromptInputLine({
				description = "(wezterm) Set workspace title:",
				action = wezterm.action_callback(function(win, pane, line)
					if line then
						wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
					end
				end),
			}),
		},
		{
			key = "b",
			mods = "SHIFT|CTRL",
			action = act.PromptInputLine({
				description = "(wezterm) Create new workspace:",
				action = wezterm.action_callback(function(window, pane, line)
					if line then
						window:perform_action(
							act.SwitchToWorkspace({
								name = line,
							}),
							pane
						)
					end
				end),
			}),
		},
		-- コマンドパレット表示
		{ key = "p", mods = "SUPER", action = act.ActivateCommandPalette },
		-- Tab移動
		{ key = "d", mods = "SHIFT|CTRL", action = act.ActivateTabRelative(1) },
		{ key = "s", mods = "SHIFT|CTRL", action = act.ActivateTabRelative(-1) },
		-- Tab新規作成
		{ key = "e", mods = "SHIFT|CTRL", action = act({ SpawnTab = "CurrentPaneDomain" }) },
		-- Tabを閉じる
		{ key = "w", mods = "SHIFT|CTRL", action = act({ CloseCurrentTab = { confirm = true } }) },
		-- Tab入れ替え
		{ key = "c", mods = "SHIFT|CTRL", action = act({ MoveTabRelative = 1 }) },
		{ key = "x", mods = "SHIFT|CTRL", action = act({ MoveTabRelative = -1 }) },

		-- 画面フルスクリーン切り替え
		{ key = "Enter", mods = "ALT", action = act.ToggleFullScreen },

		-- コピーモード
		{ key = "y", mods = "SHIFT|CTRL", action = act.ActivateCopyMode },
		-- コピー
		{ key = "c", mods = "SUPER", action = act.CopyTo("Clipboard") },
		-- 貼り付け
		{ key = "v", mods = "SUPER", action = act.PasteFrom("Clipboard") },

		-- Pane作成
		{ key = ",", mods = "SHIFT|CTRL", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
		{ key = ".", mods = "SHIFT|CTRL", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
		-- Paneを閉じる
		{ key = "m", mods = "SHIFT|CTRL", action = act({ CloseCurrentPane = { confirm = true } }) },
		-- Pane移動
		{ key = "i", mods = "SHIFT|CTRL", action = act.ActivatePaneDirection("Up") },
		{ key = "j", mods = "SHIFT|CTRL", action = act.ActivatePaneDirection("Left") },
		{ key = "k", mods = "SHIFT|CTRL", action = act.ActivatePaneDirection("Down") },
		{ key = "l", mods = "SHIFT|CTRL", action = act.ActivatePaneDirection("Right") },
		-- Paneリサイズモード
		{ key = "h", mods = "SHIFT|CTRL", action = act.ActivateKeyTable({ name = "resize_pane", one_shot = false }) },
		-- Pane swap
		{ key = "n", mods = "SHIFT|CTRL", action = act.PaneSelect({ mode = "SwapWithActiveKeepFocus" }) },
		-- 選択中のPaneのみ表示
		{ key = "p", mods = "SHIFT|CTRL", action = act.TogglePaneZoomState },

		-- フォントサイズ切替
		{ key = "+", mods = "CTRL", action = act.IncreaseFontSize },
		{ key = "-", mods = "CTRL", action = act.DecreaseFontSize },
		-- フォントサイズのリセット
		{ key = "0", mods = "CTRL", action = act.ResetFontSize },

		-- タブ切替 Cmd + 数字
		{ key = "1", mods = "SUPER", action = act.ActivateTab(0) },
		{ key = "2", mods = "SUPER", action = act.ActivateTab(1) },
		{ key = "3", mods = "SUPER", action = act.ActivateTab(2) },
		{ key = "4", mods = "SUPER", action = act.ActivateTab(3) },
		{ key = "5", mods = "SUPER", action = act.ActivateTab(4) },
		{ key = "6", mods = "SUPER", action = act.ActivateTab(5) },
		{ key = "7", mods = "SUPER", action = act.ActivateTab(6) },
		{ key = "8", mods = "SUPER", action = act.ActivateTab(7) },
		{ key = "9", mods = "SUPER", action = act.ActivateTab(-1) },

		-- Deleteキーの有効化
		{ key = "Delete", mods = "NONE", action = act.SendString("\x1b[3~") },
		-- nvim は Kitty keyboard protocol で \x1b[27u を期待するため分岐
		{
			key = "Escape",
			mods = "NONE",
			action = wezterm.action_callback(function(win, pane)
				local proc = pane:get_foreground_process_name()
				if proc:find("nvim") then
					win:perform_action(act.SendString("\x1b[27u"), pane)
				else
					win:perform_action(act.SendString("\x1b"), pane)
				end
			end),
		},

		-- スクロール
		{ key = ":", mods = "SHIFT|CTRL", action = act.ScrollByLine(-3) },
		{ key = "?", mods = "SHIFT|CTRL", action = act.ScrollByLine(3) },
		-- 設定再読み込み
		{ key = "r", mods = "SHIFT|CTRL", action = act.ReloadConfiguration },
		-- WezTerm終了
		{ key = "q", mods = "SUPER", action = act.QuitApplication },
	},
	-- キーテーブル
	-- https://wezfurlong.org/wezterm/config/key-tables.html
	key_tables = {
		-- Paneサイズ調整 Ctrl+Shift+H で起動
		resize_pane = {
			{ key = "u", action = act.AdjustPaneSize({ "Up", 1 }) },
			{ key = "o", action = act.AdjustPaneSize({ "Left", 1 }) },
			{ key = "a", action = act.AdjustPaneSize({ "Down", 1 }) },
			{ key = "i", action = act.AdjustPaneSize({ "Right", 1 }) },
			{ key = "Enter", action = "PopKeyTable" },
		},
		-- copyモード Ctrl+Shift+Y で起動
		copy_mode = {
			-- 移動
			{ key = "h", mods = "NONE", action = act.CopyMode("MoveLeft") },
			{ key = "j", mods = "NONE", action = act.CopyMode("MoveDown") },
			{ key = "k", mods = "NONE", action = act.CopyMode("MoveUp") },
			{ key = "l", mods = "NONE", action = act.CopyMode("MoveRight") },
			{ key = "LeftArrow", mods = "NONE", action = act.CopyMode("MoveLeft") },
			{ key = "DownArrow", mods = "NONE", action = act.CopyMode("MoveDown") },
			{ key = "UpArrow", mods = "NONE", action = act.CopyMode("MoveUp") },
			{ key = "RightArrow", mods = "NONE", action = act.CopyMode("MoveRight") },
			-- 最初と最後に移動
			{ key = "^", mods = "NONE", action = act.CopyMode("MoveToStartOfLineContent") },
			{ key = "$", mods = "NONE", action = act.CopyMode("MoveToEndOfLineContent") },
			-- 左端に移動
			{ key = "0", mods = "NONE", action = act.CopyMode("MoveToStartOfLine") },
			{ key = "o", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEnd") },
			{ key = "O", mods = "NONE", action = act.CopyMode("MoveToSelectionOtherEndHoriz") },
			--
			{ key = ";", mods = "NONE", action = act.CopyMode("JumpAgain") },
			-- 単語ごと移動
			{ key = "w", mods = "NONE", action = act.CopyMode("MoveForwardWord") },
			{ key = "b", mods = "NONE", action = act.CopyMode("MoveBackwardWord") },
			{ key = "e", mods = "NONE", action = act.CopyMode("MoveForwardWordEnd") },
			-- ジャンプ機能 t f
			{ key = "t", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = true } }) },
			{ key = "f", mods = "NONE", action = act.CopyMode({ JumpForward = { prev_char = false } }) },
			{ key = "T", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = true } }) },
			{ key = "F", mods = "NONE", action = act.CopyMode({ JumpBackward = { prev_char = false } }) },
			-- 一番下へ
			{ key = "G", mods = "NONE", action = act.CopyMode("MoveToScrollbackBottom") },
			-- 一番上へ
			{ key = "g", mods = "NONE", action = act.CopyMode("MoveToScrollbackTop") },
			-- viweport
			{ key = "H", mods = "NONE", action = act.CopyMode("MoveToViewportTop") },
			{ key = "L", mods = "NONE", action = act.CopyMode("MoveToViewportBottom") },
			{ key = "M", mods = "NONE", action = act.CopyMode("MoveToViewportMiddle") },
			-- スクロール
			{ key = "b", mods = "CTRL", action = act.CopyMode("PageUp") },
			{ key = "f", mods = "CTRL", action = act.CopyMode("PageDown") },
			{ key = "d", mods = "CTRL", action = act.CopyMode({ MoveByPage = 0.5 }) },
			{ key = "u", mods = "CTRL", action = act.CopyMode({ MoveByPage = -0.5 }) },
			-- 範囲選択モード
			{ key = "v", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Cell" }) },
			{ key = "v", mods = "CTRL", action = act.CopyMode({ SetSelectionMode = "Block" }) },
			{ key = "V", mods = "NONE", action = act.CopyMode({ SetSelectionMode = "Line" }) },
			-- コピー
			{ key = "y", mods = "NONE", action = act.CopyTo("Clipboard") },

			-- コピーモードを終了
			{
				key = "Enter",
				mods = "NONE",
				action = act.Multiple({ { CopyTo = "ClipboardAndPrimarySelection" }, { CopyMode = "Close" } }),
			},
			{ key = "Escape", mods = "NONE", action = act.CopyMode("Close") },
			{ key = "c", mods = "CTRL", action = act.CopyMode("Close") },
			{ key = "q", mods = "NONE", action = act.CopyMode("Close") },
		},
	},
}
