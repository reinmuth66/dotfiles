local volume = sbar.add("item", "volume", {
	position = "right",
	drawing = false,
})

volume:subscribe("volume_change", function(env)
	local vol = tonumber(env.INFO)

	if vol == nil then
		return
	elseif vol == 0 then
		volume:set({ drawing = true, icon = "󰖁", label = "" })
	else
		volume:set({ drawing = false })
	end
end)
