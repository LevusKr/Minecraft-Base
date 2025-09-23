--[[
    Resources-Library
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
local resources = {};

attribute_DEFAULT = function ()
        
    return nil, "Not implemented";

end

local attribute_caller = {
    
    __call = function(self, attribute)
    
        local attribute_function = self[ attribute ];

        if attribute_function then

            --- #1: pcall's success  #2: pcall's error OR function's result  #3: function's potential error message
            local success_execution, result_execution, result_function = pcall( attribute_function );
        
            if not success_execution then

                return nil, result_execution;

            end

            --- 'result_execution' will be resouce provider function's result OR nil and an error message
            return result_execution, result_function;

        else
        
            return nil, "Invalid attribute " .. tostring( attribute );

        end

    end
}


--- Globally loaded table to-be overloaded at runtime with backend data functions to be called upon request of respective attribute
resources.energy = {
    ready = attribute_DEFAULT,
    amount = attribute_DEFAULT,
    capacity = attribute_DEFAULT,
    ["in"] = attribute_DEFAULT,
    out = attribute_DEFAULT,
    transfer = attribute_DEFAULT,
    transfer_max = attribute_DEFAULT
};

setmetatable(resources.energy, attribute_caller);



--- Globally loaded table to-be overloaded at runtime with backend data functions to be called upon request of respective attribute
resources.oxygen = {
    ready = attribute_DEFAULT,
    amount = attribute_DEFAULT,
    capacity = attribute_DEFAULT,
    ["in"] = attribute_DEFAULT,
};

setmetatable(resources.oxygen, attribute_caller);
--




--<< API Methods >>--

function resources.generic(operation, provider, attributes, options)

    attributes = attributes or {};
    options = options or {};

    --- Wrap single string-attribute with table
    if type( attributes.energy ) ~= "table" then

        attributes.energy = { attributes.energy };

    end

    if type( attributes.oxygen ) ~= "table" then

        attributes.oxygen = { attributes.oxygen };

    end
    ---


    local packet_request = Packet:create(
        modem.address,
        provider,
        constants.port.logistics,
        constants.packet.data,
        {
            operation = "resources_" .. tostring( operation ),
            payload = attributes
        }
    );

    --- Success of sending packet and optional error message
    local success, result = packet_request:send{open_port = true, encrypt = false};

    result = result or "Timed out"; --- If no error message is present, use default error message

    if not success then
        return success, result;
    end


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

        --- This not only awaits completion of the future, but also finishing of handler calls.
        --- This ensures, that the above success handler sets 'success' and 'result' accordingly before returning
        -- TODO: when running sync, the handlers are only registered after the future already completed, thus being run directly, so no await neccessary here
        response_future:await( true );

        return success, result;

    end

    return response_future;

end

--- Gets a single attribute or a list of attributes from given resource provider.  Options: async:bool; timeout:num
--- @param provider string Remote name or address
--- @param attributes table {energy={*attributes*}, oxygen={*attributes*}}
--- @param options table {async:boolean, timeout:number}
function resources.get(provider, attributes, options)

    return resources.generic("get", provider, attributes, options);

end

--- Fetches a list of valid attributes from given resouce provider.  Options: async:bool; timeout:num
function resources.fetch(provider, attributes, options)

    return resources.generic("fetch", provider, attributes, options);

end

--- (Un-)Subscribes to a single attribute or a list of attributes from given resource provider.  Options: async:bool; timeout:num
function resources.pubsub(provider, attributes, options)

    return resources.generic("pubsub", provider, attributes, options);

end

--<< API Methods end >>--




--- Return API Methods as table
return resources;