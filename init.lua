block_vps = {}
local http_api = minetest.request_http_api()
assert(http_api ~= nil, "Add 'block_vps' to secure.http_mods and restart server")

local mod_path = core.get_modpath(core.get_current_modname())
local mod_storage = minetest.get_mod_storage()
-- block users from banned IPs from even attempting to connect, not recommand as it freezes other server activity
local block_before_login = core.settings:get_bool("block_vps_block_before_login") or false

assert(loadfile(mod_path .. "/api.lua"))(http_api)
dofile(mod_path .. "/iphub.lua")
dofile(mod_path .. "/iphub_legacy.lua")
dofile(mod_path .. "/nastyhosts.lua")
-- block other mods from register data source till better security code can be written
block_vps.regsiter_datasource = nil

local function create_reject_message(ip, isp, kicked)
	local note = ","
	if kicked then note = ".\nConnect from an unblocked IP address to be able to use this account," end
	return string.format("\nCreating new accounts from this IP address (%s) is blocked,\nas it appears to be belong to a hosting/VPN/proxy provider (%s)" ..
			"%s\nplease contact the server owner if this is an error.", ip, isp, note)
end
	
local function log_block(name, ip, isp, datasource, kicked)
	local prefix = "Blocking %q connecting"
	if kicked then prefix = "Kicked %q connected" end
	core.log("action", string.format("[block_vps] " .. prefix .. " from %q as the IP address appears to belong to %q (datasource = %q).", name, ip, isp, datasource))
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
		-- Check if the account has yet to connect from a valid IP
		if mod_storage:get_int(name) == 1 then
			block_vps.get_ip_info(ip, function(ip, info)
				if info and info.is_blocked then
					-- if the player tries to connect from another banned IP kick and log.
					log_block(name, ip, info.isp, info.api, true)
					minetest.kick_player(name, create_reject_message(ip, info.isp, true))
				else
					mod_storage:set_int(name, 0) -- there doesn't seem to be a function to erase a key?
				end
			end)
		end
	end)
	
	core.register_on_newplayer(function(player)
		local name = player:get_player_name()
		block_vps.get_ip_info(core.get_player_ip(name), function(ip, info)
			if true or info and info.is_blocked then
				--[[
					If the IP the player created the account with is banned,
					kick them, log the event and record that they need to login with a normal IP to use the account in mod storage
				--]]
				mod_storage:set_int(name, 1)
				log_block(name, ip, info.isp, info.api, true)
				minetest.kick_player(name, create_reject_message(ip, info.isp, true))
			end
		end)
	end)
end

core.register_chatcommand("get_ip_info", {
	params = "<ip_address>",
	description = "Display IP address information",
	privs = {server=true},
	func = function(name, param)
		param = param:trim()
		if param == "" then
			return false, "IP address needed"
		end
		local ip = param:match("^([^ ]+)")
		block_vps.get_ip_info(ip, function(ip, info)
			if not info then
				core.chat_send_player(name, string.format("Failed to get IP info for %q", ip))
			else
				local message = string.format("\nIP Info for %q\nData Source: %s\nBlocked: %s\nISP: %q\nASN: %d\nHost Name: %s\n",
							ip, info.api, tostring(info.is_blocked), info.isp, info.asn, info.hostname)
				if info.country then
					message = message .. "Country: " .. info.country .. "\n"
				end
				core.chat_send_player(name, message)
			end
		end)
	end,
})
