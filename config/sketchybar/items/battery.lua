local battery = sbar.add("item", "battery", {
	position = "right",
	update_freq = 120,
})

local function update()
	sbar.exec("pmset -g batt", function(batt_info)
		if batt_info == nil then
			return
		end

		local charge = tonumber(batt_info:match("(%d+)%%"))
		if charge == nil then
			return
		end

		local icon
		if charge >= 90 then
			icon = ""
		elseif charge >= 60 then
			icon = ""
		elseif charge >= 30 then
			icon = ""
		elseif charge >= 10 then
			icon = ""
		else
			icon = ""
		end

		if batt_info:find("AC Power") then
			icon = ""
		end

		battery:set({ icon = icon, label = charge .. "%" })
	end)
end

battery:subscribe({ "routine", "system_woke", "power_source_change" }, update)
