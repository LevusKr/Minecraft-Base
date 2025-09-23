--[[
    File-Utils-Library
    This library provides enhanced functionality for files,
    such as reading and writing.
--]]


-- Libraries and components
local event = require("event");

local filesystem = require("filesystem");
--

-- Data tables
local utils_file = {};

local handles = {};
--




--<< API Methods >>--

--- Reads data from file. 'file' is either a path or a file handle
-- TODO: refactor ambigous error messages
function utils_file.read(file, options)

    options = options or {};


    local is_handle = type( file ) == "table";


    if not is_handle and not filesystem.exists( file ) then

        return false, "Not existing";

    end


    if not is_handle then

        file = io.open(file, "r" .. (options.binary and "b" or ""));

        if not file then

            return false, "File not found";

        end

    end


    local result = file:read(options.count or "*a");

    if not options.keep_open then

        file:close();

        file = nil;

    end



    return true, result, file;

end

function utils_file._read(path, binary)

    --- If file doesn't exist, return nil
    if not filesystem.exists(path) then
        return nil;
    end
    

    local data = {}
    local file = io.open(path, "r"..(binary and "b" or ""));

    if file then
        data = file:read("*a");
        file:close();
    end

    return data;

end


function utils_file.write(file, data, options)

    options = options or {};


    local is_handle = type( file ) == "table";


    if not is_handle then

        filesystem.makeDirectory( filesystem.path( file ) );


        file = io.open(file, (options.append and "a" or "w") .. (options.binary and "b" or ""));

        if not file then

            return false, "File not found";

        end

    end



    local _file, error = file:write( data );

    if not _file then

        return false, error;

    end

    file = _file;


    if not options.keep_open then

        file:flush();
        file:close();

        file = nil;

    end



    return true, "result", file;

end

function utils_file._write(path, data, append, binary)

    local file = type(path) == "string" and assert(io.open(path, (append and "a" or "w")..(binary and "b" or ""))) or path; -- open file in write or append mode. additionally binary

    if file then

        file:write(data);
        file:flush();
        file:close();
        return true;

    end


    return false;

end


function utils_file.list(directory, path)

    local path_filesystem = filesystem.get(path or directory);

    if not path_filesystem then

        return false, "No valid filesystem";

    end


    if not path_filesystem.exists( directory ) then

        return false, "Not existing";

    end


    if not path_filesystem.isDirectory( directory ) then

        return false, "Not a directory";

    end



    local list = path_filesystem.list( directory );

    
    return true, list;

end

--<< API Methods end >>--




--- Return API Methods as table
return utils_file;