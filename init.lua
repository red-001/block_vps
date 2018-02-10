block_vps = {}
local http_api = minetest.request_http_api()
local mod_path = core.get_modpath(core.get_current_modname())
local mod_storage = minetest.get_mod_storage()
local block_before_login = true -- block users from banned IPs from even attempting to connect, not recommand as it freezes other server activity

assert(http_api ~= nil, "Add 'block_vps' to secure.http_mods and restart server")
assert(loadfile(mod_path .. "/api.lua"))(http_api)
dofile(mod_path .. "/iphub.lua")
dofile(mod_path .. "/iphub_legacy.lua")

local function create_reject_message(ip, isp, kicked)
	local note = ","
	if kicked then note = ".\nConnect from an unblocked IP address to be able to use this account," end
	return string.format("\nCreating new accounts from this IP address (%s) is blocked,\nas it appears to be belong to a hosting/VPN/proxy provider (%s)" ..
			"%s\nplease contact the server owner if this is an error.", ip, isp, note)
end
	
local function log_block(name, ip, isp, datasource, kicked)
	local prefix = "Blocking '%s' connecting"
	if kicked then prefix = "Kicked '%s' connected" end
	core.log("action", string.format("[block_vps] " .. prefix .. " from '%s' as the IP address appears to belong to '%s' (datasource = %s).", name, ip, isp, datasource))
end

if block_before_login then
	core.register_on_prejoinplayer(function(name, ip)
		if not core.player_exists(name) then
			local ip_info = block_vps.get_ip_info_sync(ip)
			if ip_info and ip_info.is_blocked then
				log_block(name, ip, ip_info.isp, ip_info.api)
				return create_reject_message(ip, ip_info.isp)
			end
		end
	end)
else
	core.register_on_prejoinplayer(function(name, ip)
		if mod_storage:get_int(name) == 1 then
			block_vps.get_ip_info(ip, function(ip, info)
				if info and info.is_blocked then
					log_block(name, ip, info.isp, info.api, true)
					minetest.kick_player(name, create_reject_message(ip, info.isp, true))
				else
					mod_storage:set_int(name, 0)
				end
			end)
		end
	end)
	
	core.register_on_newplayer(function(player)
		local name = player:get_player_name()
		block_vps.get_ip_info(core.get_player_ip(name), function(ip, info)
			if true or info and info.is_blocked then
				mod_storage:set_int(name, 1)
				log_block(name, ip, info.isp, info.api, true)
				minetest.kick_player(name, create_reject_message(ip, info.isp, true))
			end
		end)
	end)
end
