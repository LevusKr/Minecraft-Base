--[[
    String-Utils-Library
    This library provides enhanced functionality for strings,
    such as formatting, XXX and manipulating.
--]]


-- Libraries and components
local utils = require("cluster/utils");

local term = require("term");
--

-- Data tables
local utils_string = {};
--




--<< API Methods >>--

--- Checks if given string is null or empty
--- @param str string
--- @return boolean true if string is null or empty, false otherwise
function utils_string.is_null_or_empty(str)

    return not str or str == "";

end

--- Trims leading and trailing whitespace from given string
--- @param str string
--- @return string
function utils_string.trim(str)

    if str == nil then
        return "";
    end

    return tostring( str ):match("^%s*(.-)%s*$") or "";

end

--- Shortens given string 'str' down to 'size_max' and places an 'indicator'-string in the beginning, middle or end, depending on whether the first, first and last or last characters are visible, which is defined via 'visible'
--- @param str string
--- @param size_max integer
--- @param visible string
--- @param indicator string
--- @return string
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

--- Split string 'str' by 'separator'
--- @param str string
--- @param separator string? Default: " "
--- @return table
function utils_string.split(str, separator)

    str = tostring( str );
    separator = separator or " ";

    local parts = {};

    for part in str:gmatch("%S+") do
        parts[ #parts + 1 ] = part;
    end


    return parts;

end

--- Parses a boolean, string ("true"/"false"/"1"/"0") or nil into a boolean with fallback default
--- @param value any
--- @param default boolean?
--- @return boolean?
function utils_string.parse_boolean(value, default)

    if value == nil then

        return default;

    elseif type( value ) == "boolean" then

        return value;

    elseif type( value ) == "string" then

        local lower = value:lower();

        if lower == "true" or lower == "1" or lower == "yes" then
            return true;
        elseif lower == "false" or lower == "0" or lower == "no" then
            return false;
        end

    end


    return default;

end

--- Conditionally writes text to terminal (or optional stream) when 'condition' is truthy
--- @param condition any
--- @param text string
--- @param stream table?
function utils_string.cwrite(condition, text, stream)

    if condition then

        if stream then
            stream:write( tostring( text ) );
        else
            term.write( tostring( text ) );
        end

    end

end

--<< API Methods end >>--




--- Return API Methods as table
return utils_string;