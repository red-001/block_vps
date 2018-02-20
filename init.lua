block_vps = {}
local http_api = minetest.request_http_api()
assert(http_api ~= nil, "Add 'block_vps' to secure.http_mods and restart server")

local mod_path = core.get_modpath(core.get_current_modname())
local mod_storage

-- support older minetest versions
if minetest.get_mod_storage then
	mod_storage = minetest.get_mod_storage()
end

-- support older minetest versions
function block_vps.get_setting(name)
	if core.settings then
		return core.settings:get(name)
	else
		return core.setting_get(name)
	end
end

local block_type = block_vps.get_setting("block_vps_type") or "activation"

assert(loadfile(mod_path .. "/api.lua"))(http_api)
dofile(mod_path .. "/iphub.lua")
dofile(mod_path .. "/iphub_legacy.lua")
dofile(mod_path .. "/nastyhosts.lua")
-- block other mods from register data source till better security code can be written
block_vps.register_datasource = nil

local function create_reject_message(ip, isp)
	local message
	if block_type ~= "kick" then
		message = "\nCreating new accounts "
	else
		message = "\nConnecting "
	end
	message = message .. "from this IP address (%s) is blocked,\nas it appears to be belong to a hosting/VPN/proxy provider (%s)" ..
				"%s\nplease contact the server owner if this is an error."
	local note = ","
	if block_type == "activation" then 
		note = ".\nConnect from an unblocked IP address to be able to use this account,"
	end
	return string.format(message, ip, isp, note)
end
	
local function log_block(name, ip, isp, datasource, kicked)
	local prefix = "Blocking %q connecting"
	if kicked then prefix = "Kicked %q connected" end
	core.log("action", string.format("[block_vps] " .. prefix .. " from %q as the IP address appears to belong to %q (datasource = %q).", name, ip, isp, datasource))
end

if block_type == "creation" then
	core.register_on_prejoinplayer(function(name, ip)
		if not core.player_exists(name) then
			local ip_info = block_vps.get_ip_info_sync(ip)
			if ip_info and ip_info.is_blocked then
				log_block(name, ip, ip_info.isp, ip_info.api)
				return create_reject_message(ip, ip_info.isp)
			end
		end
	end)
elseif block_type == "activation" then
	-- support older minetest versions
	assert(mod_storage ~= nil, "Your minetest version doesn't support mod storage, " ..
		"it is required if 'block_vps_type' is set to 'activation' please change it to any other support setting ('none', 'kick', 'creation')")
	
	local default_privs = core.string_to_privs(core.settings:get("default_privs"))
	
	core.register_on_joinplayer(function(player)
		local name = player:get_player_name()
		-- Check if the account has yet to connect from a valid IP
		if mod_storage:get_int(name) == 1 then
			block_vps.get_ip_info(core.get_player_ip(name), function(ip, info)
				if info and info.is_blocked then
					-- if the player tries to connect from another banned IP kick and log.
					log_block(name, ip, info.isp, info.api, true)
					minetest.kick_player(name, create_reject_message(ip, info.isp))
				else
					-- give the player back the default privs we took
					core.set_player_privs(name, default_privs)
					mod_storage:set_string(name, "") -- only way to erase a mod storage key
				end
			end)
		end
	end)
	
	core.register_on_newplayer(function(player)
		local name = player:get_player_name()
		-- revoke all of the players privs so they don't try to exploit the small delay between connection and IP lookup end.
		core.set_player_privs(name, {})
		block_vps.get_ip_info(core.get_player_ip(name), function(ip, info)
			if info and info.is_blocked then
				--[[
					If the IP the player created the account with is banned,
					kick them, log the event and record that they need to login with a normal IP to use the account in mod storage
				--]]
				mod_storage:set_int(name, 1)
				log_block(name, ip, info.isp, info.api, true)
				minetest.kick_player(name, create_reject_message(ip, info.isp, true))
			else
				-- give the player back the default privs we took
				core.set_player_privs(name, default_privs)
			end
		end)
	end)
elseif block_type == "kick" then
	core.register_on_joinplayer(function(player)
		local name = player:get_player_name()
		if core.check_player_privs(name, {bypass_ip_check=true}) then
			return
		end
		block_vps.get_ip_info(core.get_player_ip(name), function(ip, info)
			if info and info.is_blocked then
				log_block(name, ip, info.isp, info.api, true)
				minetest.kick_player(name, create_reject_message(ip, info.isp))
			end
		end)
	end)
end

core.register_privilege("bypass_ip_check", "Stops the users IP from being check on join by block_vps")

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
