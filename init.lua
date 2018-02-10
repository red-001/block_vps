block_vps = {}
local http_api = minetest.request_http_api()
local mod_path = core.get_modpath(core.get_current_modname())

assert(http_api ~= nil, "Add 'block_vps' to secure.http_mods and restart server")
assert(loadfile(mod_path .. "/api.lua"))(http_api)
dofile(mod_path .. "/iphub.lua")
dofile(mod_path .. "/iphub_legacy.lua")

core.register_on_prejoinplayer(function(name, ip)
		block_vps.get_ip_info(ip, function(ip, info)
			print(name .. " " .. dump(info) .. ip)
		end)
		if not core.player_exists(name) then
			local ip_info = block_vps.get_ip_info_sync(ip)
			if ip_info and ip_info.block == 1 then
				core.log("info", string.format("[block_vps] Blocked '%s' connecting from '%s' as the IP address appears to belong to '%s'.", name, ip, ip_info.isp))
				return string.format("\nCreating new accounts from this IP address (%s) is blocked,\nas it appears to be belong to a hosting/VPN/proxy provider (%s)," ..
					"\nplease contact the server owner if this is an error.", ip, ip_info.isp)
			end
		end
end)
