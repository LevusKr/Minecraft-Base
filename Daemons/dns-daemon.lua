--[[
    DNS-Daemon
    This DNS-Client will run on startup and intercept attempts to send network messages via modem, thus replacing hostnames with real addresses.
    If the receiver is no modem guid, but some sort of hostname AND there is a dns entry for it, the message will eventually
    be forwarded to the corresponding address.
--]]


-- Libraries and components
local component = require("component");
local constants = require("cluster/constants");
local dns = require("cluster/dns-library");
local event = require("event");
local Future = require("cluster/future");
local network = require("cluster/network");
local utils = require("cluster/utils");
--

-- Variables and Constants
local hostname = utils.internal.hostname();

local address_dns = network.address_dns();
local address_core = network.address_core();

local address_local = component.modem.address;


local component_invoke = nil; --- Original method, for later restoring
--

-- Data tables
--





--<< RC Handling >>--

--- RC API start function - 'Intercept component.modem.send' method call
function start()

    component_invoke = component.invoke;

    component.invoke = function(address, method, ...)

        local component_type = component.type( address );

        --- If invoked method is not modem.send or modem.broadcast, do nothing
        if component_type == "modem" and (method == "send" or method == "broadcast") then

            local args = {...};
            local receiver = method == "send" and args[1] or "*";
            local skip_lookup = false;

            local success = false;
            local response = nil;



            --- If receiver already is an address instead a resolveable hostname OR '*' for broadcasting, skip lookup
            if network.validate_address( receiver ) or receiver == "*" then

                skip_lookup = true;

            end


            --- If receiver is pointing at own modem, send internal modem_message, skip lookup
            if receiver == hostname or receiver == address or receiver == "localhost" or receiver == "127.0.0.1" then

                event.push(
                    "modem_message",
                    address,
                    address,
                    args[2],
                    0,
                    select(3, table.unpack( args ))
                );


                skip_lookup = true;

            end


            --- If no valid response is found yet, search local hosts for match
            if not skip_lookup then

                if receiver == constants.name.dns then

                    if not address_dns then

                        event.onError("Configure DNS address in '/etc/network.cfg'.");

                    end

                    response = address_dns;
                    skip_lookup = true;

                elseif receiver == constants.name.core then

                    if not address_core then

                        event.onError("Configure Core address in '/etc/network.cfg'.");

                    end

                    response = address_core;
                    skip_lookup = true;

                end

            end


            --- If lookup doing should indeed be done, do it
            if not skip_lookup then

                --- Finally retrieve valid address from dns cache, which optionally queries dns server (see dns-library)
                success, response = dns.lookup( receiver );

                if not success then

                    event.onError("Unable to resolve hostname '" .. tostring( receiver ) .. "': " .. tostring( response ));

                end

            end


            --- If response is anything but nil, replace hostname with an valid address in modem.send's arguments
            args[1] =
                response ~= nil
                and response
                or args[1]
            ;


            --- Invoke component method with modified args and return result
            return component_invoke(address, method, table.unpack( args ));

        else

            return component_invoke(address, method, ...);

        end

    end



    --- Automatically create dns entry for local address, normally this is done along registration at core so just redundancy checking here
    --- Defaults to local hostname and modem address
    dns.create(_, _, true):on_failure(
        function(result)

            if result ~= "Hostname already exists" then

                event.onError("Failed to create own dns entry: " .. tostring( result ));

            end

        end
    );

end

--- RC API stop function - Reset 'component.invoke' function
function stop()

    component.invoke = component_invoke;

end

--<< RC Handling >>--