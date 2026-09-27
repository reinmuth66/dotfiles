local colors = require("colors")

local swap = sbar.add("item", "swap", {
	position = "right",
	update_freq = 20,
	icon = {
		string = "",
		font = { style = "Italic" },
		color = colors.swap.default,
	},
	label = {
		font = { style = "Italic" },
		color = colors.swap.default,
	},
})

local function update()
	sbar.exec("sysctl vm.swapusage", function(result)
		if result == nil then
			return
		end

		local used = result:match("used = ([%d%.]+M)")
		if used == nil then
			return
		end

		local color = colors.swap.default
		if used ~= "0.00M" then
			color = colors.swap.alert
		end

		swap:set({
			icon = { color = color },
			label = { string = used, color = color },
		})
	end)
end

swap:subscribe({ "routine", "forced" }, update)
