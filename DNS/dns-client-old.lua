--[[
    DNS-Client
    This DNS-Client will run on startup and intercept attempts to send
    network messages via modem, thus replacing hostnames with real addresses.
    If the receiver is no modem guid, but some sort of hostname
    AND there is a dns entry for it, the message will eventually
    be forwarded to the corresponding address.
--]]

-- Libraries and components
local utils = require("cluster/utils");
local dns = require("dns");
local component = require("component");
local computer = require("computer");
--

-- cache: {1 = {name = "hostname", address = "exampleaddress", ttl = 1000}, 2 = {...}, ...}
dnsCache = setmetatable({}, {
  __index = function(dnsCache, key)
    for index, entry in pairs(dnsCache) do
      if entry.name == key or entry.address == key then
        return entry;
      end
    end
  end
});


local invoke = nil;

-- RC API start function - intercept component.modem.send function
function start()
  invoke = component.invoke;

  component.invoke = function(address, method, ...)
    local componentType = component.type(address);

    if componentType == "modem" and method == "send" then
      local args = {...};
      local hostname = args[1]; -- Maybe not a modem address, but a hostname TODO: check if address, then skip dns lookup


      local response = nil;
      if dnsCache[hostname] and computer.uptime() < dnsCache[hostname].ttl then
        response = dnsCache[hostname].address;
      else
        local success, lookupResult = dns.lookup(hostname);
        if success then -- TODO: if not success store n/a in cache -> of course then don't use "n/a" as address but address
          response = lookupResult;
          cache(hostname, response, constants.ttl.dns);
        end
      end

      if response then
        args[1] = response;
      end

      local invokeResult = {invoke(address, method, table.unpack(args))};


      return table.unpack(invokeResult);
    end


    return invoke(address, method, ...);
  end
end

-- RC API stop function - reset component.invoke function
function stop()
  component.invoke = invoke;
end


-- Add entry to the DNS cache
function cache(_name, _address, _ttl)
  if dnsCache[_name] then
    dnsCache[_name].ttl = computer.uptime() + (_ttl or constants.ttl.dns);
    return;
  end

  table.insert(dnsCache, {
    name = _name,
    address = _address,
    ttl = computer.uptime() + (_ttl or constants.ttl.dns)
  });

  if dnsCache["core"] then
    dnsCache["core"].ttl = math.huge;
  end
end
