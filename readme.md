# JNAP DeviceList Lua API for Nginx

This script publishes **ISC DHCPD active leases** as a **Linksys JNAP** JSON endpoint (`/JNAP/`) responding to  
`http://linksys.com/jnap/devicelist/GetDevices`.

### Why This Is Useful
This allows `homeassistant.components.linksys_smart` (the [Linksys Smart](https://github.com/home-assistant/core/tree/dev/homeassistant/components/linksys_smart) device tracker) to work seamlessly with a **non-Linksys router**, such as a self-hosted Linux system running ISC DHCPD.  
In short: it makes your self-hosted DHCP server act like a Linksys router for Home Assistant device presence tracking.

## Installation

1. Install dependencies:
```
apt install nginx libnginx-mod-http-lua lua-cjson
```

2. Copy the Lua script:
```
mkdir -p /etc/nginx/lua
cp jnap-devicelist.lua /etc/nginx/lua/
```

3. Enable in your Nginx configuration:
```
lua_package_path "/etc/nginx/lua/?.lua;;";

location /JNAP/ {
  content_by_lua_file /etc/nginx/lua/jnap-devicelist.lua;
}
```

4. Reload:
```
nginx -t && systemctl reload nginx
```


## Usage

Query the endpoint:
```
curl -X POST http://router.local/JNAP/
-H "Content-Type: application/json"
-d '{"action": "http://linksys.com/jnap/devicelist/GetDevices"}'
```


Expected response format:
```
{
  "responses": [{
    "output": {
      "devices": [{
        "knownMACAddresses": ["11:22:33:44:55:66"],
        "connections": true,
        "properties": {"userDeviceName": "Donald's iPhone"}
      }]
    }
  }]
}
```

---

Developed with assistance from [Perplexity AI](https://www.perplexity.ai/).

