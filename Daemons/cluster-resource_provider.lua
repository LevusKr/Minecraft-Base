--[[
    Resource Provider
    This daemon exposes generic resource device interfaces to the cluster network.
    Node implementations implement/override the generic resource functions and provide data.
    This avoids every resource related Node Implementation to implement this functionality seperatly
    by providing a generic, abstract interface
--]]


-- Files and Configurations
--

-- Libraries and components
local codec  = require("cluster/codec")
local constants = require("cluster/constants");
local resources = require("cluster/resources");
local Packet = require("cluster/network_packet");

local component = require("component");
local event = require("event");

local modem = component.modem;
--

-- Variables and constants
local timer_publish = 0;
local interval_publish = 10; --- Publish data every n seconds
--

-- Data tables
local subscriptions = {
    -- user123 = {
    --     energy = {},
    --     oxygen = {}
    -- }
};
--





--<< Daemon Functions >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if packet_request.port ~= constants.port.logistics then
        return;
    end



    local client = packet_request.sender;
    local operation = packet_request.data.operation;
    local attributes = packet_request.data.payload;

    event.onError("Client '" .. tostring( client ) .. "' requested '" .. tostring( operation ) .. "' with payload '" .. tostring( attributes ) .. "'");



    local response = {
        success = true, --- No real point of failure here
        result = {
            energy = {},
            oxygen = {}
        }
    };


    --- Fetch resource attribute(s) by calling (hopefully) implemented provider functions. See 'resources.lua' library
    if operation == "resources_get" then

        --- Wrap single string-attribute with table
        if type( attributes.energy ) ~= "table" then

            attributes.energy = { attributes.energy };

        end

        if type( attributes.oxygen ) ~= "table" then

            attributes.oxygen = { attributes.oxygen };

        end
        ---


        local call_helper = function (type, attribute)
            local result, error = resources[ type ]( attribute );

            response.result[ type ][ attribute ] = {
                success = result ~= nil,
                result = result or error or "Unknown error at "..tostring( attribute )
            };
        end

        --- Iterates over all specified types and their respective specified attributes
        for type, typed_attributes in pairs( attributes ) do

            --- Calls all available attributes
            if typed_attributes[1] == "ALL" then

                for attribute, _ in pairs( resources[ type ] ) do

                    call_helper(type, attribute);

                end

            --- Calls only specified attributes
            else

                for _, attribute in pairs( attributes[ type ] ) do

                    call_helper(type, attribute);

                end

            end

        end

    --- Fetch list of available (implemented) resource attributes
    elseif operation == "resources_fetch" then

        --- Iterates over all specified types --and their respective specified attributes--
        --- Since this operation fetches all available attributes, 'attributes' will only contain the type(s) to fetch, no typed attributes
        for type, _ in pairs( attributes ) do

            for attribute, _ in pairs( resources[ type ] ) do

                response.result[ type ][ #response.result[type] + 1 ] = attribute;

            end

        end

    --- Subscribe to 
    elseif operation == "resources_pubsub" then

        for type, typed_attributes in pairs( attributes ) do

            for attribute, do_subscribe in pairs( typed_attributes ) do

                --- Adds/removes attribute of type to active subscriptions of client
                subscriptions[ client ][ type ][ attribute ] = do_subscribe;

                --- If the subscription state for this attribute changed
                response.result[ type ][ attribute ] = subscriptions[ client ][ type ][ attribute ] ~= do_subscribe

            end

        end

    end



    local send_success, send_result = packet_request:send_response( response );

    if send_success then
        event.onError("Response to client '"  .. tostring( client ) ..  "': '" .. tostring( response.success ) .. " - " .. tostring( response.result ) .. "'\n");
    else
        event.onError("Response to client '"  .. tostring( client ) ..  "' couldn't be sent: " .. tostring( send_result ) .. "\n");
    end

end

--- Fetches and publishes subscribed attributes to subscribers   TODO: don't just fetch and pub every few seconds (see 'interval_publish' on top) but rather when values actually change
function subscription_publish()

    modem.open( constants.port.logistics );

    for client, attributes in pairs( subscriptions ) do

        local data_publish = {
            success = false,
            result = {}
        }


        local call_helper = function (type, attribute)
            local result, error = resources[ type ]( attribute );

            data_publish.result[ type ][ attribute ] = {
                success = result ~= nil,
                result = result or error or "Unknown error at "..tostring( attribute )
            };
        end

        --- Iterates over all specified types and their respective specified attributes
        for type, typed_attributes in pairs( attributes ) do

            --- Calls all available attributes
            if typed_attributes[1] == "ALL" then

                for attribute, _ in pairs( resources[ type ] ) do

                    call_helper(type, attribute);

                end

            --- Calls only specified attributes
            else

                for _, attribute in pairs( typed_attributes ) do

                    call_helper(type, attribute);

                end

            end

        end


        -- TODO: check success of sending packet here?
        Packet:create(
            modem.address,
            client,
            constants.port.logistics,
            constants.packet.data,
            data_publish
        ):send();

    end

end

--<< Daemon Functions end >>--




--<< API Methods >>--


--<< API Methods end >>--




--<< RC Handling >>--

--- RC API start function - Listen to network messages
function start()

    modem.open( constants.port.logistics );

    event.listen("cluster_data", data_handle);

    timer_publish = event.timer(interval_publish, subscription_publish, math.huge);


    event.onError("Resource Provider started.");

end

--- RC API stop function - XXX
function stop()

    event.ignore("cluster_data", data_handle);

    event.cancel( timer_publish );


    event.onError("Resource Provider stopped.");

end

--<< RC Handling >>--