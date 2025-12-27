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
    local current_lease = {}
    
    for line in content:gmatch("[^\r\n]+") do
        line = line:gsub("^%s*(.-)%s*$", "%1")  -- trim
        
        if line:match("^lease%s+") then
            -- Extract IP from lease line, but we need MAC from hardware line later
            in_lease = true
            current_lease = { fields = {} }
        elseif in_lease and line:match("^%s*hardware ethernet%s+") then
            -- Extract MAC address
            local mac = line:match("^%s*hardware ethernet%s+([%x:]+);")
            if mac then
                current_lease.mac = mac:lower():gsub(":", ""):gsub("%-", "")
            end
        elseif in_lease and line:match("^%s*([^%s]+)%s+\"?(.-)\"?;%s*$") then
            local key, value = line:match("^%s*([^%s]+)%s+\"?(.-)\"?;%s*$")
            if key and value then
                current_lease.fields[key:gsub("%-", "-")] = value  -- Normalize keys
            end
        elseif in_lease and line:match("^%}") then
            -- End of lease - check if active and has required data
            local binding_state = current_lease.fields["binding state"] or ""
            if binding_state:match("active") and current_lease.mac then
                local hostname = current_lease.fields["client%-hostname"] or 
                                current_lease.fields["vendor%-class%-identifier"] or 
                                ""
                if hostname ~= "" then
                    -- Format MAC back to standard colon format
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
                end
            end
            in_lease = false
            current_lease = {}
        end
    end
    
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

