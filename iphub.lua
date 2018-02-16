local ip_hub_api = {}
local API_KEY = block_vps.get_setting("iphub_api_key") or 'YOUR_API_KEY_HERE'

local function is_base_64(string)
	if type(string) == "string" and string ~= "" then
		return string:match("[^%w^/^+^=]") == nil
	end
end

function ip_hub_api:generate_request(ip)
	local request = {}
	request.url = "http://v2.api.iphub.info/ip/" .. ip
	request.extra_headers = {"X-Key: " .. API_KEY}
	return request
end

function ip_hub_api:is_api_available()
	return is_base_64(API_KEY) and not self.bad_key and not self.temp_disable
end

function ip_hub_api:is_response_valid(response)
	if response.succeeded == false or response.code ~= 200 then
		if response.code == 403 then
			core.log("error", "[block_vps] Bad API_KEY supplied.")
			self.bad_key = true
		elseif response.timeout then
			core.log("error", "[block_vps] Getting IP info took too long.")
		elseif response.code == 429 then
			core.log("error", "[block_vps] Too many IP lookups, got rate limited")
			self.temp_disable = true
			-- wait 60 seconds if we are rate limited before trying again
			core.after(60, function()
					self.temp_disable = false
				end)
		else
			core.log("error", "[block_vps] Failed to look up ip address, error code :" .. tostring(response.code))
		end
		return false
	end
	return true
end

function ip_hub_api:handle_response_data(ip, data_json)
	local info = {}
	local data = core.parse_json(data_json)
	info.is_blocked = (data.block == 1)
	info.isp = data.isp
	info.asn = data.asn
	info.hostname = data.hostname
	if data.countryName ~= "Unknown" then
		info.country = data.countryName
	end
	if data.countryCode ~= "ZZ" then
		info.country_code = data.countryCode
	end
	return info
end

block_vps.register_datasource("iphub", ip_hub_api)