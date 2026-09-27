local volume = sbar.add("item", "volume", {
	position = "right",
})

volume:subscribe("volume_change", function(env)
	local vol = tonumber(env.INFO)
	local icon = "󰖁"

	if vol == nil then
		return
	elseif vol >= 60 then
		icon = "󰕾"
	elseif vol >= 30 then
		icon = "󰖀"
	elseif vol >= 1 then
		icon = "󰕿"
	end

	volume:set({ icon = icon, label = vol .. "%" })
end)
