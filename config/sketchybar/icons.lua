local DEFAULT_ICON = ":default:"

local app_icons = {
	["Activity Monitor"] = ":activity_monitor:",
	["App Store"] = ":app_store:",
	["Bambu Studio"] = ":bambu_studio:",
	["Calculator"] = ":calculator:",
	["Calendar"] = ":calendar:",
	["カレンダー"] = ":calendar:",
	["Dia"] = ":dia:",
	["Discord"] = ":discord:",
	["FaceTime"] = ":face_time:",
	["Finder"] = ":finder:",
	["Freeform"] = ":freeform:",
	["System Preferences"] = ":gear:",
	["System Settings"] = ":gear:",
	["システム設定"] = ":gear:",
	["Google Chrome"] = ":google_chrome:",
	["iPhone Mirroring"] = ":iphone_mirroring:",
	["Mail"] = ":mail:",
	["メール"] = ":mail:",
	["Maps"] = ":maps:",
	["マップ"] = ":maps:",
	["Messages"] = ":messages:",
	["メッセージ"] = ":messages:",
	["Microsoft Excel"] = ":microsoft_excel:",
	["Microsoft PowerPoint"] = ":microsoft_power_point:",
	["Microsoft Teams"] = ":microsoft_teams:",
	["Microsoft Teams (work or school)"] = ":microsoft_teams:",
	["Microsoft Word"] = ":microsoft_word:",
	["Music"] = ":music:",
	["ミュージック"] = ":music:",
	["Notes"] = ":notes:",
	["メモ"] = ":notes:",
	["Passwords"] = ":passwords:",
	["Preview"] = ":pdf:",
	["プレビュー"] = ":pdf:",
	["Photos"] = ":photos:",
	["Podcasts"] = ":podcasts:",
	["Reminders"] = ":reminders:",
	["リマインダー"] = ":reminders:",
	["Safari"] = ":safari:",
	["Spotify"] = ":spotify:",
	["Terminal"] = ":terminal:",
	["ターミナル"] = ":terminal:",
	["TextEdit"] = ":textedit:",
	["Weather"] = ":weather:",
	["WezTerm"] = ":wezterm:",
	["Zed"] = ":zed:",
}

local M = {}

function M.app(name)
	if name == nil then
		return DEFAULT_ICON
	end

	return app_icons[name] or DEFAULT_ICON
end

return M
