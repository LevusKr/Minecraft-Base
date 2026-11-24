--[[
    Energy-Library
    This library provides functionality for fetching remote energy device's attributes,
    such as the current energy level, current energy transfer etc.
--]]


-- Libraries and components
local constants = require("cluster/constants");
local Packet = require("cluster/network_packet");

local component = require("component");
local event = require("event");

local modem = component.modem;
--

-- Data tables
local energy = {};

local attribute_DEFAULT = function ()
        
    return nil, "Not implemented";

end

energy.energy_attributes = {
    ENERGY_READY = attribute_DEFAULT,
    ENERGY_CURRENT = attribute_DEFAULT,
    ENERGY_MAX = attribute_DEFAULT,
    ENERGY_IN = attribute_DEFAULT,
    ENERGY_OUT = attribute_DEFAULT,
    ENERGY_TRANSFER = attribute_DEFAULT,
    ENERGY_TRANSFER_MAX = attribute_DEFAULT
};

setmetatable(energy.energy_attributes, {
    
    __call = function(self, attribute)
    
        local energy_attribute_function = self[ attribute ];

        if energy_attribute_function then

            --- #1: pcall's success  #2: pcall's error OR function's result  #3: function's potential error message
            local success_execution, result_execution, result_function = pcall( energy_attribute_function );
        
            if not success_execution then

                return false, result_execution;

            end

            --- 'result_execution' will be energy provider function's result or nil and an error message
            return result_execution, result_function;

        else
        
            return false, "Invalid attribute " .. tostring( attribute );

        end

    end
});
--




--<< API Methods >>--

--- Gets a single attribute or a list of attributes from given energy provider.  Options: async:bool; timeout:num
function energy.get(provider, attributes, options)

    if type( attributes ) ~= "table" then

        attributes = { attributes };

    end

    options = options or {};



    local packet_request = Packet.create(
        modem.address,
        provider,
        constants.port.energy,
        constants.packet.data,
        {
            operation = "data_energy",
            payload = attributes
        }
    );

    packet_request:send( {open_port = true} );


    local success = false;
    local result = "Timed out";

    local response_future = packet_request:await_response(

        options.async,
        options.timeout

    );

    response_future:on_success(
        function(packet_response)
            
            success, result = packet_response.data.success, packet_response.data.result;

        end
    ):on_failure(
        function(error)

            result = error or "Timed Out 2";

        end
    );



    if not options.async then

        response_future:await( true );

        return success, result;

    end

    return response_future;

end

--- Fetches a list of valid attributes from given energy provider
function energy.fetch(provider, options)

    options = options or {};



    local packet_request = Packet.create(
        modem.address,
        provider,
        constants.port.energy,
        constants.packet.data,
        {
            operation = "data_energy_attributes"
        }
    );

    packet_request:send( {open_port = true} );


    local success = false;
    local result = "Timed out";

    local response_future = packet_request:await_response(

        options.async,
        options.timeout

    );

    response_future:on_success(
        function(packet_response)
            
            success, result = packet_response.data.success, packet_response.data.result;

        end
    ):on_failure(
        function(error)

            result = error or result;

        end
    );



    if not options.async then

        response_future:await( true );

        return success, result;

    end

    return response_future;

end

--- Subscribes to a single attribute or a list of attributes from given energy provider.
function energy.subscribe(provider, attributes, options)

    if type( attributes ) ~= "table" then

        attributes = { attributes };

    end

    options = options or {};



    local packet_request = Packet.create(
        modem.address,
        provider,
        constants.port.energy,
        constants.packet.data,
        {
            operation = "data_energy_subscribe",
            payload = attributes
        }
    );

    packet_request:send( {open_port = true} );


    local success = false;
    local result = "Timed out";

    local response_future = packet_request:await_response(

        options.async,
        options.timeout

    );

    response_future:on_success(
        function(packet_response)
            
            success, result = packet_response.data.success, packet_response.data.result;

        end
    ):on_failure(
        function(error)

            result = error or "Timed Out 2";

        end
    );



    if not options.async then

        response_future:await( true );

        return success, result;

    end

    return response_future;

end

--- Unsubscribes from a single attribute or a list of attributes from given energy provider.
function energy.unsubscribe(provider, options)

    options = options or {};



    local packet_request = Packet.create(
        modem.address,
        provider,
        constants.port.energy,
        constants.packet.data,
        {
            operation = "data_energy_unsubscribe",
        }
    );

    packet_request:send( {open_port = true} );


    local success = false;
    local result = "Timed out";

    local response_future = packet_request:await_response(

        options.async,
        options.timeout

    );

    response_future:on_success(
        function(packet_response)
            
            success, result = packet_response.data.success, packet_response.data.result;

        end
    ):on_failure(
        function(error)

            result = error or "Timed Out 2";

        end
    );



    if not options.async then

        response_future:await( true );

        return success, result;

    end

    return response_future;

end

--<< API Methods end >>--




--- Return API Methods as table
return energy;