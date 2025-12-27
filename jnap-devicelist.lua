-- Lua script for nginx: /etc/nginx/lua/jnap-devicelist.lua
local lfs = require "lfs"
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
            in_lease = true
            current_lease = { mac = line:match("lease%s+([%x:%.%-]+)"), fields = {} }
        elseif in_lease and line:match("^%}") then
            -- Check if active binding
            local binding_state = current_lease.fields["binding state"] or ""
            if binding_state:match("active") then
                local mac = current_lease.mac:lower():gsub(":", ""):gsub("%-", "")
                local hostname = current_lease.fields["client%-hostname"] or 
                                current_lease.fields["vendor%-class%-identifier"] or 
                                ""
                if hostname ~= "" and mac ~= "" then
                    table.insert(devices, {
                        knownMACAddresses = {string.upper(mac:gsub("(.)(.)", "%1:%2"))},
                        connections = true,
                        properties = {userDeviceName = hostname}
                    })
                end
            end
            in_lease = false
            current_lease = {}
        elseif in_lease and line:match("^%s*([^%s]+)%s+\"?(.-)\"?;%s*$") then
            local key, value = line:match("^%s*([^%s]+)%s+\"?(.-)\"?;%s*$")
            if key and value then
                current_lease.fields[key] = value
            end
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

