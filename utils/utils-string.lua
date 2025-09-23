--[[
    String-Utils-Library
    This library provides enhanced functionality for strings,
    such as formatting, XXX and manipulating.
--]]


-- Libraries and components
local utils = require("cluster/utils");
--

-- Data tables
local utils_string = {};
--




--<< API Methods >>--

--- Shortens given string 'str' down to 'size_max' and places an 'indicator'-string in the beginning, middle or end, depending on whether the first, first and last or last characters are visible, which is defined via 'visible'
function utils_string.dotate(str, size_max, visible, indicator)

    str = tostring( str );
    local size_str = #str;
    size_max = size_max or 15;
    visible = visible or "middle";
    indicator = indicator or "...";

    
    if not (size_str > size_max) then
        return str
    end



    local size_max_str = size_max - #indicator;
    local _str = "";

    --- Start: Show as much characters as allowed per 'size_max' at the beginning and place 'indicator'-string to indicate that rest of string is hidden
    if visible == "start" then

        _str =
            str:sub(1, size_max_str) ..
            indicator
        ;

    --- Middle: Show as much characters as allowed per 'size_max' at the beginning and end and place 'indicator'-string in the middle to indicate that middle rest of string is hidden
    elseif visible == "middle" then

        _str = 
            str:sub(1, utils.math.round(size_max_str / 2)) ..
            indicator ..
            str:sub(#str - utils.math.round(size_max_str / 2), size_str)
        ;

    --- End: Show as much characters as allowed per 'size_max' at the end and place 'indicator'-string in the beginning to indicate that beginning rest of string is hidden
    elseif visible == "end" then

        _str =
            indicator ..
            str:sub(size_str - size_max_str, size_str)
        ;

    end

    

    return _str;
    
end

function utils_string.split(str, separator)

    str = tostring( str );
    separator = separator or " ";

    local parts = {};

    for part in str:gmatch("%S+") do
        parts[ #parts + 1 ] = part;
    end


    return parts;

end

--<< API Methods end >>--




--- Return API Methods as table
return utils_string;