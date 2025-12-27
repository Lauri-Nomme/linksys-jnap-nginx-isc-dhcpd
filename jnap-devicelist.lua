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
            -- Check for end of lease - more flexible matching
            if line:match("^%s*}$") or line:match("^%}$") or line == "}" then
                ngx.log(ngx.DEBUG, "End lease detected: '" .. line .. "', binding: " .. (current_lease.fields["binding state"] or "nil") .. 
                              ", mac: " .. (current_lease.mac or "nil") ..
                              ", hostname: " .. (current_lease.fields["client-hostname"] or "nil"))
                
                local binding_state = current_lease.fields["binding state"] or ""
                if binding_state:match("active") and current_lease.mac then
                    local hostname = current_lease.fields["client-hostname"] or 
                                    current_lease.fields["vendor-class-identifier"] or 
                                    "unknown"
                    
                    -- Format MAC: 5c17cf2d6cc9 -> 5C:17:CF:2D:6C:C9
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
                -- Extract MAC: hardware ethernet 5c:17:cf:2d:6c:c9;
                local mac = line:match("^%s*hardware ethernet%s+([%x:]+);")
                if mac then
                    current_lease.mac = mac:lower():gsub(":", ""):gsub("%-", "")
                    ngx.log(ngx.DEBUG, "Found MAC: " .. mac)
                end
            elseif line:match("^%s*([^%s=]+)") then
                -- Handle all key-value lines more robustly
                -- Matches: binding state active;
                -- Matches: client-hostname "Ahmed-s-iPhone";
                -- Matches: set vendor-class-identifier = "android-dhcp-13";
                local key, value = line:match("^%s*([^%s=]+)%s+[\"=]?([^\";]+)[\";]?$")
                if key and value then
                    key = key:gsub("^set%s+", ""):gsub("%s+", "")
                    current_lease.fields[key] = value
                    ngx.log(ngx.DEBUG, "Field '" .. key .. "': '" .. value .. "'")
                end
            end
        end
    end
    
    -- Handle case where file ends without closing brace
    if in_lease then
        ngx.log(ngx.DEBUG, "File ended with open lease, processing final lease")
        local binding_state = current_lease.fields["binding state"] or ""
        if binding_state:match("active") and current_lease.mac then
            local hostname = current_lease.fields["client-hostname"] or 
                            current_lease.fields["vendor-class-identifier"] or "unknown"
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
            ngx.log(ngx.INFO, "Added final device: " .. hostname .. " (" .. formatted_mac .. ")")
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

-- Main handler
handle_jnap()

