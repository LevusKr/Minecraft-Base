--[[
    DNS-Library
    This library provides functionality to communicate with the remote DNS-Server.
--]]


-- Libraries and components
local utils = require("cluster/utils");
local Cache = require("cluster/cache");
local component = require("component");
local constants = require("cluster/constants");
local event = require("event");
local _event = require("cluster/event");
local network = require("cluster/network");
local Packet = require("cluster/network_packet");

local modem = component.modem;
--

-- Data tables
local dns = {};

local cache_dns = Cache.create(
    function(receiver)

        local success, result = dns.lookup(receiver, true); --- 'refresh' flag set to 'true'

        if success then

            return result;

        end

        event.onError("Unable to resolve hostname for '" .. tostring( receiver ) .. "': " .. tostring( result ));

    end,
    constants.ttl.dns
);
-- 




--<< API Methods >>--

--- Operate at DNS-Server with given arguments and return Future object
function dns.operate(operation, entry, address, option, async)

    local packet_request = Packet.create(
        modem.address,
        constants.name.dns,
        constants.port.dns,
        constants.packet.data,
        {
            operation = operation or "query",
            entry = entry or utils.internal.hostname(),
            address = address or modem.address,
            option = option
        }
    );

    --- Success of sending packet and optional error message
    local success, result = packet_request:send{open_port = true, encrypt = true}; -- TODO: encryption

    result = result or "DNS-Server unreachable"; --- If no error message is present, use default error message

    if not success then
        return success, result;
    end


    local response_future = packet_request:await_response( async );

    -- if not async then
        response_future:on_success(
            function(packet_response)

                success = packet_response.data.success;
                result = packet_response.data.result;

            end
        ):on_failure(
            function(error)

                result = error or result;

            end
        ):on_completion(
            function()

                response_future.result = {
                    success = success,
                    result = result
                }

            end
        );
    -- end



    if async then

        return response_future;

    else

        return success, result, response_future;

    end

end

--- Attempts to create new dns entry
function dns.entry_create(name, address, async)

    return dns.operate(
        "create",
        name,
        address,
        _,
        async
    );

end
dns.create = dns.entry_create

--- Attempts to delete entry (name or address)
function dns.entry_delete(entry, async)

    return dns.operate(
        "delete",
        entry,
        _,
        _,
        async
    );

end
dns.delete = dns.entry_delete

--- Attempts to query for entry (name or address). Result is cached, this can be avoided with boolean parameter 'refresh'
function dns.entry_query(entry, refresh, async)

    --- (Possibly) cached result
    if not refresh then

        return cache_dns:get( entry );

    --- Refreshed result
    else

        return dns.operate(
            "query",
            entry,
            _,
            _,
            async
        );

    end

end
dns.query = dns.entry_query
dns.lookup = dns.entry_query

--- Attempts to edit existing dns entry
function dns.entry_edit(name, address, name_new, async)

    return dns.operate(
        "edit",
        name,
        address,
        name_new,
        async
    );

end
dns.edit = dns.entry_edit

--<< API Methods end >>--




--- Return API Methods as table
return dns;