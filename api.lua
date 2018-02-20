local api_base = {}
local http_api = ...
local cache_time = tonumber(block_vps.get_setting("block_vps_cache_time")) or 30000 -- ~8 hours
local max_try_count = tonumber(block_vps.get_setting("block_vps_max_try")) or 3 -- how many API do we try to use before aborting
local enabled_sources = string.split(block_vps.get_setting("block_vps_datasources")
	or "iphub, iphub_legacy, nastyhosts", ",")

local function gen_stub(name)
	return function(self) error("'" .. name .. "' must be implemented") end
end

function busy_wait(s)
	local ntime = os.clock() + s
	repeat until os.clock() > ntime
end

api_base.generate_request = gen_stub("generate_request")

api_base.handle_response_data = gen_stub("handle_response_data")

function api_base:is_api_available()
	return not self.temp_disable
end

function api_base:is_data_stale(data)
	return (data.last_update + cache_time) < os.time()
end

function api_base:sync_http_fetch(request)
	local handle = http_api.fetch_async(request)
	local res = http_api.fetch_async_get(handle)
	local time_taken = 0
	while not res.completed do
		busy_wait(0.005)
		time_taken = time_taken + 0.005
		if time_taken > 1 then
			return { succeeded=false, timeout=true }
		end
		res = http_api.fetch_async_get(handle)
	end
	return res
end


-- a bit messy there should be an easier way to implement this but this works
local recent_max_size = 15
local function record_request_result(self, result)
	if not self.recent_requests then
		self.recent_requests = {}
		for i = 1, recent_max_size do
			self.recent_requests[i] = 1
		end
	end

	if not self.current_offset then self.current_offset = 1 end

	self.recent_requests[self.current_offset] = result
	self.current_offset = self.current_offset + 1
	if self.current_offset > recent_max_size then
		self.current_offset = 1
	end
end

local function get_recent_success_rate(self)
	local total = 0
	for _, v in ipairs(self.recent_requests) do
		total = total + v
	end
	return recent_max_size / total
end

function api_base:is_response_valid(response)
	if response.succeeded == false or response.code ~= 200 then
		record_request_result(self, 0)
		if response.timeout then
			core.log("error", "[block_vps] Getting IP info took too long.")
		else
			core.log("error", "[block_vps] Failed to look up ip address, error code :" .. tostring(response.code))
		end
		local success_rate = get_recent_success_rate(self)
		if success_rate < 0.6 then
			self.recent_requests = {}
			self.temp_disable = true
			core.after(1200, function() self.temp_disable = false end)
			core.log("error", "[block_vps] disabled '" + self.name + "' for 20 minutes due to high look up failure rate ( > 40%)")
		elseif success_rate <= 0.8 then
			self.temp_disable = true
			core.after(300, function() self.temp_disable = false end)
		core.log("warning", "[block_vps] disabled '" + self.name + "' for 5 minutes due to high look up failure rate ( >= 20%)")
		end
		return false
	end
	record_request_result(self, 1)
	return true
end
		
local function gen_request(self, ip)
	local request = self:generate_request(ip)
	assert(type(request) == "table" and type(request.url) == "string",
			"generate_request must return a table compatible with the HTTP API")
	return request
end
		
local function handle_response(self, response, ip)
	if self:is_response_valid(response) then
		local info = self:handle_response_data(ip, response.data)
		if info and not info.last_update then
			info.last_update = os.time()
			info.api = self.name
		end
		return info
	else
		return nil
	end
end

function api_base:get_ip_info_sync(ip)
	local response = self:sync_http_fetch(gen_request(self, ip))
	return handle_response(self, response, ip)
end

local in_progress = {}
function api_base:get_ip_info_async(ip, callback, ...)
	local request = gen_request(self, ip)
	in_progress[http_api.fetch_async(request)] = {callback = callback, ip = ip, api = self, arg = {...}}
end

local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer >= 0.5 then
		timer = 0
		for k,v in pairs(in_progress) do
			local res = http_api.fetch_async_get(k)
			if res.completed then
				local info = handle_response(v.api, res, v.ip)
				v.callback(v.ip, info, unpack(v.arg))
				in_progress[k] = nil
			end
		end
	end
end)

local datasources = {}
-- todo: add security checks to this and allow other mods to use it
function block_vps.register_datasource(name, api)
	setmetatable(api, {__index = api_base})
	api.name = name
	datasources[name] = api
end

local function get_datasource(ignore)
	for _, name in ipairs(enabled_sources) do
		name = name:trim()
		local skip = false
		for _, ignored in ipairs(ignore) do
			if ignored == name then
				skip = true
			end
		end
		if not skip then
			local current_source = datasources[name]
			if current_source and current_source:is_api_available() then
				return current_source, name
			end
		end
	end
	core.log("error", "[block_vps] No datasource is currently usable.")
end

local ip_info_cache = {}

function block_vps.get_ip_info_sync(ip)
	-- Check if we already looked up that IP recently and return from cache
	local info = ip_info_cache[ip]
	if info then
		local source = datasources[info.api]
		if not source:is_data_stale(info) then
			return info
		end
	end
	
	local ignored_datasources = {}
	local try_count = 1
	while true do
		-- Get the API
		local source, name = get_datasource(ignored_datasources)
		if not source then
			return nil -- ran out of working APIs...
		end
		local info = source:get_ip_info_sync(ip)
		if info then
			ip_info_cache[ip] = info
			return info
		else
			try_count = try_count + 1
			if try_count > max_try_count then
				return nil -- too many attempts aborting
			end
			table.insert(ignored_datasources, name)
		end
	end
end

local function get_info_async(ip, callback, try_count, ignored_datasources, ...)
	local source, name = get_datasource(ignored_datasources)
		if not source then
			callback(ip, nil, ...) -- ran out of working APIs...
	end
	source:get_ip_info_async(ip, function(ip, ip_info, ...)
			try_count = try_count + 1
			if not ip_info and try_count <= max_try_count then
				table.insert(ignored_datasources, name)
				get_info_async(ip, callback, try_count, ignored_datasources, ...)
			else
				-- might be better to return stale information if available?
				ip_info_cache[ip] = ip_info
				callback(ip, ip_info, ...)
			end
		end,
		...)
end

function block_vps.get_ip_info(ip, callback, ...)
	-- Check if we already looked up that IP recently and return from cache
	local info = ip_info_cache[ip]
	if info then
		local source = datasources[info.api]
		if not source:is_data_stale(info) then
			callback(ip, info, ...)
			return
		end
	end
	local ignored_datasources = {}
	local try_count = 1
	get_info_async(ip, callback, try_count, ignored_datasources, ...)
end
