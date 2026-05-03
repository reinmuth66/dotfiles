local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.automatically_reload_config = true
config.font = wezterm.font("Moralerspace Neon HW")
config.font_size = 12.0
config.use_ime = true
config.macos_forward_to_ime_modifier_mask = "SHIFT|CTRL"
config.default_cursor_style = "SteadyBar"
config.hide_mouse_cursor_when_typing = true
config.window_background_opacity = 0.7
config.macos_window_background_blur = 20

----------------------------------------------------
-- Tab
----------------------------------------------------
-- タイトルバーを非表示
config.window_decorations = "RESIZE"
-- タブバーの表示
config.show_tabs_in_tab_bar = true
-- タブが一つの時は非表示
config.hide_tab_bar_if_only_one_tab = true
-- falseにするとタブバーの透過が効かなくなる
-- config.use_fancy_tab_bar = false

-- タブバーの透過
config.window_frame = {
	inactive_titlebar_bg = "none",
	active_titlebar_bg = "none",
}

-- タブバーを背景色に合わせる
config.window_background_gradient = {
	colors = { "#161821" },
}

-- タブの追加ボタンを非表示
config.show_new_tab_button_in_tab_bar = false
-- nightlyのみ使用可能
-- タブの閉じるボタンを非表示
config.show_close_tab_button_in_tabs = false

-- タブ同士の境界線を非表示 + Iceberg Dark カラーパレット
config.colors = {
	foreground = "#c6c8d1",
	background = "#161821",
	cursor_bg = "#c6c8d1",
	cursor_fg = "#161821",
	selection_bg = "#1e2132",
	selection_fg = "#c6c8d1",
	ansi = { "#1e2132", "#e27878", "#b4be82", "#e2a478", "#84a0c6", "#a093c7", "#89b8c2", "#c6c8d1" },
	brights = { "#6b7089", "#e98989", "#c0ca8e", "#e9b189", "#91afd7", "#ada0d3", "#95c4ce", "#d2d4de" },
	tab_bar = {
		inactive_tab_edge = "none",
	},
}

-- タブの形をカスタマイズ
-- タブの左側の装飾
local SOLID_LEFT_ARROW = wezterm.nerdfonts.ple_left_half_circle_thick
-- タブの右側の装飾
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.ple_right_half_circle_thick

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local background = "#1e2132"
	local foreground = "#FFFFFF"
	local edge_background = "none"
	if tab.is_active then
		background = "#84a0c6"
		foreground = "#FFFFFF"
	end
	local edge_foreground = background
	local raw_title = tab.active_pane.title
	if raw_title == "" then
		raw_title = tab.active_pane.foreground_process_name:match("([^/]+)$") or "shell"
	end
	local title = " " .. wezterm.truncate_right(raw_title, max_width - 1) .. " "
	return {
		{ Background = { Color = edge_background } },
		{ Foreground = { Color = edge_foreground } },
		{ Text = SOLID_LEFT_ARROW },
		{ Background = { Color = background } },
		{ Foreground = { Color = foreground } },
		{ Text = title },
		{ Background = { Color = edge_background } },
		{ Foreground = { Color = edge_foreground } },
		{ Text = SOLID_RIGHT_ARROW },
	}
end)

wezterm.on("gui-startup", function()
	local _, _, window = wezterm.mux.spawn_window({})
	window:gui_window():maximize()
end)

----------------------------------------------------
-- keybinds
----------------------------------------------------
config.disable_default_key_bindings = true
config.keys = require("keybinds").keys
config.key_tables = require("keybinds").key_tables

return config
