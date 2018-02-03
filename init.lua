local http_api = minetest.request_http_api()
local API_KEY = 'YOUR_API_KEY_HERE'
local cache_time = 30000 -- ~8 hours

block_vps = {}

local ip_info_cache = {}

function sleep(s)
  local ntime = os.clock() + s
  repeat until os.clock() > ntime
end

local function is_base_64(string)
	if type(string) == "string" and string ~= "" then
		return string:match("[^%w^/^+^=]") == nil
	end
end

local function sync_http_fetch(request)
	local handle = http_api.fetch_async(request)
	local res = http_api.fetch_async_get(handle)
	local time_taken = 0
	while not res.completed do
		sleep(0.005)
		time_taken = time_taken + 0.005
		if time_taken > 1 then
			return { succeeded=false, timeout=true }
		end
		res = http_api.fetch_async_get(handle)
	end
	return res
end

local function generate_request(ip)
	local request = {}
	request.url = "http://v2.api.iphub.info/ip/" .. ip
	request.extra_headers = {"X-Key: " .. API_KEY}
	return request
end

local function generate_old_request(ip)
	return { url = "http://legacy.iphub.info/api.php?showtype=4&ip=" .. ip }
end

-- todo rewrite this part of the code
local function translate_old_response(ip, response)
	if response.succeeded == false or response.code ~= 200 then
		return response
	end
	local old_info = minetest.parse_json(response.data)
	local new_info = {}
	new_info.ip = ip
	new_info.block = old_info.proxy
	new_info.hostname = old_info.hostname
	new_info.countryCode = old_info.countryCode
	new_info.countryName = old_info.countryName
	if old_info.countryCode == "" then
		new_info.countryCode = "ZZ"
	end
	local asn = 0
	local isp_info = string.split(old_info.asn, " ")
	if isp_info[1] then
		asn = tonumber(isp_info[1]:sub(3))
	end
	new_info.asn = asn
	new_info.isp = old_info.asn
	response.data = minetest.write_json(new_info)
	return response
end

local warning_issued = false

local function get_ip_info(ip)
	-- Check if we already looked up that IP recently and return from cache
	local info = ip_info_cache[ip]
	if info and (info.last_update + cache_time) >= os.time() then
		return info
	end
	
	-- Look up the IP with the API
	local result
	if is_base_64(API_KEY) then -- check if the API_KEY is a valid base64 string
		result = sync_http_fetch(generate_request(ip))
	else -- if it's not fallback to the old api that doesn't need it
		if not warning_issued then
			warning_issued = true
			core.log("warning", "API_KEY not set falling back to legacy API")
		end
		result = translate_old_response(ip, sync_http_fetch(generate_old_request(ip)))
	end
	if result.succeeded == false or result.code ~= 200 then
		if result.code == 403 then
			core.log("error", "[block_vps] Bad API_KEY supplied.")
		elseif result.timeout then
			core.log("error", "[block_vps] Getting IP info took too long (>1s).")
		elseif result.code == 429 then
			core.log("error", "[block_vps] Too many IP lookups, got rate limited")
		else
			core.log("error", "[block_vps] Failed to look up ip address, error code :" .. tostring(result.code))
		end
		return nil
	end
	
	-- Cache IP info
	info = minetest.parse_json(result.data)
	info.last_update = os.time()
	ip_info_cache[ip] = info
	
	return info
end
block_vps.get_ip_info = get_ip_info

core.register_on_prejoinplayer(function(name, ip)
		if not core.player_exists(name) then
			local ip_info = get_ip_info(ip)
			if ip_info and ip_info.block == 1 then
				core.log("info", string.format("[block_vps] Blocked '%s' connecting from '%s' as the IP address appears to belong to '%s'.", name, ip, ip_info.isp))
				return string.format("\nCreating new accounts from this IP address (%s) is blocked,\nas it appears to be belong to a hosting/VPN/proxy provider (%s)," ..
					"\nplease contact the server owner if this is an error.", ip, ip_info.isp)
			end
		end
end)
