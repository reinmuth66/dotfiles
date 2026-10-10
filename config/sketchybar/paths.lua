-- 複数の item が使うパス。
local home = os.getenv("HOME")

return {
	home = home,
	-- item ごとにサブディレクトリを作る
	cache = home .. "/Library/Caches/sketchybar",
}
