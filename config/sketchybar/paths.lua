-- 複数の item が使うパス。
local home = os.getenv("HOME")

-- cache の下には、item ごとにサブディレクトリを作る。
return {
	home = home,
	cache = home .. "/Library/Caches/sketchybar",
}
