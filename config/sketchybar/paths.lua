-- Paths used by multiple items.
local home = os.getenv("HOME")

-- Under cache, create a subdirectory for each item.
return {
	home = home,
	cache = home .. "/Library/Caches/sketchybar",
}
