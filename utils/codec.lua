--[[
    Codec-Library
    This library provides enhanced functionality for serialization,
    such as support of varargs and overall shorter method calls.
--]]


-- Libraries and components
local serialization = require("serialization");
--

-- Data tables
local codec = {};
--




--<< API Methods >>--

--- Wraps serialization.serialize and allows varargs as parameter. Returns tuple of encoded parameters
function codec.encode(...)

    local data = {...};
    local result = {};

    -- This returns the serialized var args in order of input as tuple
    if #data == 1 then

        return serialization.serialize( table.unpack( data ) );

    else

        for _, entry in ipairs( data ) do

            --table.insert(result, serialization.serialize( entry ));   TODO: check performance
            result[ #result + 1 ] = serialization.serialize( entry );

        end

        return table.unpack( result );

    end

end

--- Wraps serialization.unserialize and allows varargs as parameter. Returns tuple of decoded parameters
function codec.decode(...)

    local data = {...};
    local result = {};

    if #data == 1 then

        -- If decoding didn't apply, return values.
        -- This allows for passing possible string data preventive and continue without null checking return value
        local result_decode = serialization.unserialize( table.unpack( data ) );

        if result_decode then

            return result_decode;

        else

            return table.unpack( data );

        end

    else

        for _, entry in ipairs( data ) do

            --table.insert(result, serialization.unserialize( entry ));   TODO: check performance
            result[ #result + 1 ] = serialization.unserialize( entry );

        end

        return table.unpack( result );

    end

end

--<< API Methods end >>--




--- Return API Methods as table
return codec;