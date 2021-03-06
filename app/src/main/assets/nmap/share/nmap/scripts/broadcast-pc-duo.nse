description = [[
Discovers PC-DUO remote control hosts and gateways running on the LAN
]]

---
-- @usage
-- nmap --script broadcast-pc-duo
--
-- @output
-- Pre-scan script results:
-- | broadcast-pc-duo: 
-- |   PC-Duo Gateway Server
-- |     10.0.200.113 - WIN2K3SRV-1
-- |   PC-Duo Hosts
-- |_    10.0.200.113 - WIN2K3SRV-1
--

author = "Patrik Karlsson"
license = "Same as Nmap--See http://nmap.org/book/man-legal.html"
categories = { "broadcast", "safe" }

local TIMEOUT = tonumber(stdnse.get_script_args("broadcast-pc-duo.timeout"))

prerule = function() return ( nmap.address_family() == "inet") end

-- Sends a UDP probe to the server and processes the response
-- @param probe table contaning a pc-duo probe
-- @param responses table containing the responses
local function udpProbe(probe, responses)
	
	local condvar = nmap.condvar(responses)
	local socket = nmap.new_socket("udp")
	socket:set_timeout(500)

	for i=1,2 do
		local status = socket:sendto(probe.host, probe.port, probe.data)
		if ( not(status) ) then
			return "\n  ERROR: Failed to send broadcast request"
		end
	end
		
	local timeout = TIMEOUT or ( 20 / ( nmap.timing_level() + 1 ) )
	local stime = os.time()
	local hosts = {}
	
	repeat
		local status, data = socket:receive()
		if ( status ) then
			local srvname = data:match(probe.match)
			if ( srvname ) then
				local status, _, _, rhost, _ = socket:get_info()
				if ( not(status) ) then
					socket:close()
					return false, "Failed to get socket information"
				end
				-- avoid duplicates
				hosts[rhost] = srvname
			end
		end
	until( os.time() - stime > timeout )
	socket:close()
	
	local result = {}
	for ip, name in pairs(hosts) do
		table.insert(result, ("%s - %s"):format(ip,name))
	end
	
	if ( #result > 0 ) then
		result.name = probe.topic
		table.insert(responses, result)
	end
	
	condvar "signal"
end

action = function()
	
	-- PC-Duo UDP probes
	local probes = {
		-- PC-Duo Host probe
		{ 
			host = { ip = "255.255.255.255" },
			port = { number = 1505, protocol = "udp" },
			data =  bin.pack("H", "00808008ff00"),
			match= "^.........(%w*)\0",
			topic= "PC-Duo Hosts"
		},
		-- PC-Duo Gateway Server probe
		{ 
			host = { ip = "255.255.255.255" },
			port = { number = 2303, protocol = "udp" },
			data =  bin.pack("H", "20908008ff00"),
			match= "^.........(%w*)\0",
			topic= "PC-Duo Gateway Server"
		},		
	}
	
	local threads, responses = {}, {}
	local condvar = nmap.condvar(responses)
	
	-- start a thread for each probe
	for _, p in ipairs(probes) do
		local th = stdnse.new_thread( udpProbe, p, responses )
		threads[th] = true
	end

	-- wait until the probes are all done
	repeat
		condvar "wait"
		for thread in pairs(threads) do
			if coroutine.status(thread) == "dead" then
				threads[thread] = nil
			end
		end
	until next(threads) == nil
    
	table.sort(responses, function(a,b) return a.name < b.name end)
	-- did we get any responses
	if ( #responses > 0 ) then
		return stdnse.format_output(true, responses)
	end
end