-- 複数の item が使うパス。
local home = os.getenv("HOME")

return {
	home = home,
	-- 各 item のキャッシュの置き場 (item ごとにサブディレクトリを作る)
	cache = home .. "/Library/Caches/sketchybar",
}
