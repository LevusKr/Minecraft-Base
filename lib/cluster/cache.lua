--- @module 'cluster/cache'
--[[
    Cache
    This class provides functionality for creating caches, which hold data
    for a specified amount of time and after that refresh that data.
--]]


-- Libraries and components
local constants = require("cluster/constants");

local computer = require("computer");
local event = require("event");
--

-- Data tables
--- @class Cache
--- 
--- @field load function
--- @field ttl number
--- @field contents table?
--- TODO: add custom ttl when getting item from cache
local Cache = {
    contents = nil,
    ttl = constants.ttl.dns or (5*60),
    load =
    function()
        return "Cache load function not implemented";
    end
};
Cache.__index = Cache;
--




--<< Class Methods >>--

--- Instantiate new cache with a loading function and data's ttl
--- @param load function
--- @param ttl number
--- @param ... any? Additional function parameters, eventually passed to cache.refresh
--- 
--- @return Cache #New instance
function Cache.create(load, ttl, ...)

    local cache = setmetatable({
        load = load,
        ttl = ttl,
        contents = {}
    }, Cache);


    return cache;

end

--- Attempts to exectute load function and store data
--- @param key any Queried table key, passed to cache.load
--- @param ... any? Additional function parameters, passed to cache.load
function Cache:refresh(key, ...)

    local success, result = pcall(self.load, key, ...); -- TODO: allow only one return value for load function?

    --- Only set value if pcall returned without an error, otherwise 'result' will be pcall's error message
    self:set(key, success and result or nil);

    if not success then

        event.onError("Error while calling cache load function '" .. tostring( self.load ) .. "': " .. tostring( result ));

    end

    --- Only report success when pcall succeeded AND load returned a non-nil value
    return (success and result ~= nil), result;

end

--- Retrieves the key's associated value. Optionally refreshes cache before
--- @param key any
--- @param refresh boolean?
--- @param ... any? Additional function parameters, passed to cache.refresh
function Cache:get(key, refresh, ...)
    
    --- If one of the following is true, refresh cache
    if not self.contents[ key ]                         --- Key doesn't exist
        or self.contents[ key ].ttl < computer.uptime() --- Key exists, but is expired
        or refresh                                      --- Manual cache refresh
    then

        return self:refresh(key, ...);

    end


    --- Otherwise, return content as it is
    return true, self.contents[ key ].value;

end

--- Sets the key's associated value.
function Cache:set(key, value)

    if key and value then

        self.contents[ key ] = {
            value = value,
            ttl = computer.uptime() + self.ttl
        };

    end


    return value;
    
end

--<< Class Methods end >>--




--- Return class object
return Cache;