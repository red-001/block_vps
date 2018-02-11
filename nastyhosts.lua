local nasty_hosts_api = {}

function nasty_hosts_api:generate_request(ip)
	return { url = "http://v1.nastyhosts.com/" .. ip }
end

function nasty_hosts_api:handle_response_data(ip, data_json)
	local data = core.parse_json(data_json)
	local info = {}
	info.is_blocked = (data.suggestion == "deny")
	if data.asn then
		info.asn = data.asn.asn
		info.isp = data.asn.name
	else
		info.asn = 0
		info.isp = ""
	end
	if data.hostnames and data.hostnames[1] then
		info.hostname = data.hostnames[1]
	else
		info.hostname = ip
	end
	if data.country then
		if data.country.code ~= "ZZ" then
			info.country_code = data.country.code
		end
		if data.country.country ~= "Reserved" then
			info.country = data.country.country
		end
	end
	return info
end

block_vps.register_datasource("nastyhosts", nasty_hosts_api)