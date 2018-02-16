local ip_hub_api = {}

local email = block_vps.get_setting("block_vps_email") or "YOUR_EMAIL@example.com"

function ip_hub_api:generate_request(ip)
	return { url = "http://legacy.iphub.info/api.php?showtype=4&ip=" .. ip .. "&email=" ..email }
end

function ip_hub_api:is_api_available()
	return not self.temp_disable
end

function ip_hub_api:is_response_valid(response)
	if response.succeeded == false or response.code ~= 200 then
		if response.timeout then
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
	local data = core.parse_json(data_json)
	if not data then
		return nil
	end
	local asn = 0
	local isp_info = string.split(data.asn, " ")
	if isp_info[1] then
		asn = tonumber(isp_info[1]:sub(3))
	end
	isp_info[1] = ""
	
	local info = {}
	info.is_blocked = (data.proxy == 1)
	info.asn = asn
	info.isp = string.trim(table.concat(isp_info, " "))
	info.hostname = data.hostname
	if data.countryName ~= "" then
		info.country = data.countryName
	end
	if data.countryCode ~= "" then
		info.country_code = data.countryCode
	end
	return info
end

block_vps.register_datasource("iphub_legacy", ip_hub_api)