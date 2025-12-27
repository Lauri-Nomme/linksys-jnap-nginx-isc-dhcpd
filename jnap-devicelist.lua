-- Lua script for nginx: /etc/nginx/lua/jnap-devicelist.lua
local json = require "cjson"

local function read_leases_file()
    local leases_file = "/var/lib/dhcp/dhcpd.leases"
    local file = io.open(leases_file, "r")
    if not file then
        ngx.log(ngx.ERR, "Failed to open " .. leases_file)
        return {}
    end

    local content = file:read("*all")
    file:close()

    local devices = {}
    local in_lease = false
    local current_lease = { fields = {}, mac = nil }
    
    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub("^%s*(.-)%s*$", "%1")  -- trim
        
        if not in_lease and line:match("^lease%s") then
            in_lease = true
            current_lease = { fields = {}, mac = nil }
            ngx.log(ngx.DEBUG, "Starting new lease: " .. line:sub(1,50))
        elseif in_lease then
            if line == "}" then
                ngx.log(ngx.DEBUG, "End lease detected: '" .. line .. "', binding: " .. (current_lease.fields["binding"] or "nil") .. 
                              ", mac: " .. (current_lease.mac or "nil") ..
                              ", hostname: " .. (current_lease.fields["client-hostname"] or "nil"))
                
                local binding_state = current_lease.fields["binding"] or ""
                if binding_state:match("state active") and current_lease.mac then
                    local hostname = current_lease.fields["client-hostname"] or 
                                    current_lease.fields["vendor-class-identifier"] or 
                                    "unknown"
                    
                    -- Format MAC: aa22bb33cc44 -> AA:22:BB:33:CC:44
                    local formatted_mac = ""
                    for i = 1, #current_lease.mac, 2 do
                        if formatted_mac ~= "" then formatted_mac = formatted_mac .. ":" end
                        formatted_mac = formatted_mac .. current_lease.mac:sub(i,i+1):upper()
                    end
                    
                    table.insert(devices, {
                        knownMACAddresses = {formatted_mac},
                        connections = true,
                        properties = {userDeviceName = hostname}
                    })
                    ngx.log(ngx.INFO, "Added device: " .. hostname .. " (" .. formatted_mac .. ")")
                end
                in_lease = false
                current_lease = { fields = {}, mac = nil }
            elseif line:match("^%s*hardware ethernet%s+[%x:]+;") then
                -- Extract MAC: hardware ethernet aa:22:bb:33:cc:44;
                local mac = line:match("^%s*hardware ethernet%s+([%x:]+);")
                if mac then
                    current_lease.mac = mac:lower():gsub(":", ""):gsub("%-", "")
                    ngx.log(ngx.DEBUG, "Found MAC: " .. mac)
                end
			elseif line:match("^%s*set ") then
				-- Handle: set vendor-class-identifier = "android-dhcp-13";
				local key, value = line:match("^%s*set%s+([^%s=]+)%s*=%s*\"([^\"]+)\"%s*;%s*$")
				if key and value then
					current_lease.fields[key] = value
					ngx.log(ngx.DEBUG, "SET Field '" .. key .. "': '" .. value .. "'")
				end
			elseif line:match("^%s*client%-hostname ") then
				-- Handle: client-hostname "Donald's iPhone";
				local value = line:match("^%s*client%-hostname%s+\"([^\"]+)\"%s*;%s*$")
				if value then
					current_lease.fields["client-hostname"] = value
					ngx.log(ngx.DEBUG, "HOSTNAME: '" .. value .. "'")
				end
			elseif line:match("^%s*binding ") then
				-- Handle: binding state active;
				local binding = line:match("^%s*binding%s+(state%s+active)%s*;%s*$")
				if binding then
					current_lease.fields["binding"] = binding
					ngx.log(ngx.DEBUG, "BINDING: '" .. binding .. "'")
				end
			end
		end
    end
    
    ngx.log(ngx.INFO, "Total active devices found: " .. #devices)
    return devices
end

local function handle_jnap()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        ngx.status = 400
        ngx.say('{"error": "No body"}')
        return ngx.exit(ngx.HTTP_BAD_REQUEST)
    end
    
    local ok, data = pcall(json.decode, body)
    if not ok or not data.action or data.action ~= "http://linksys.com/jnap/devicelist/GetDevices" then
        ngx.status = 400
        ngx.say('{"error": "Invalid action"}')
        return ngx.exit(ngx.HTTP_BAD_REQUEST)
    end
    
    local devices = read_leases_file()
    
    local response = {
        responses = {{
            output = {
                devices = devices
            }
        }}
    }
    
    ngx.header.content_type = "application/json"
    ngx.say(json.encode(response))
end

handle_jnap()

