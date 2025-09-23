--- @module 'cluster/logger'
--[[
    Logger
    This class provides functionality for creating loggers.
--]]


-- Libraries and components
local constants = require("cluster/constants");
local log = require("cluster/log-library");
local network = require("cluster/network");
local Packet = require("cluster/network_packet");
local utils = require("cluster/utils");
local utils_file = require("cluster/utils-file");


local component = require("component");
local event = require("event");
local filesystem = require("filesystem");
local os = require("os");
--

-- Data tables
--- @class Logger
---
--- @field name string
--- @field path string|nil
--- @field print boolean
--- @field print_debug boolean
--- @field print_verbose boolean
--- @field buffer_enable boolean
--- @field buffer_size number
--- @field buffer table
--- @field file table|nil OpenOS file handle
local Logger = {
    name = "Logger",
    path = nil,
    print = true,
    print_debug = false,
    print_verbose = false,
    buffer_enable = true,
    buffer_size = constants.buffer.log,
    buffer = {},
    file = nil
};
Logger.__index = Logger;
--




--<< Class Methods >>--

--- Instantiate new logger with given name, path and other (default) settings
function Logger.create(name, path, print, print_debug, print_verbose, buffer_enable, buffer_size)

    local logger = setmetatable({
        name = name,
        path = path,
        print = print,
        print_debug = print_debug,
        print_verbose = print_verbose,
        buffer_enable = buffer_enable,
        buffer_size = buffer_size,
    }, Logger);


    filesystem.makeDirectory( filesystem.path( path ) );

    local file, file_error = io.open(path, "a");

    if not file then

        return false, file_error;

    end


    logger.file = file;
    logger.file:setvbuf(buffer_enable and "full" or "no", buffer_size);


    return true, logger;

end


--- Log given message at given level, optionally print to screen
function Logger:log(level, _message, print, write_func)
    
    local stream = io.stdout;
    
    if level == "error" then

        stream = io.stderr;

    elseif level == "warn" then

        stream = io.stdwrn;

    end


    local message = "[" .. utils.time.format() .. "] [" .. level .. "] " .. tostring(_message) .. "\n";

    --- Color debug logs magenta
    if level == "debug" then
        message = "\27[35m" .. message .. "\27[37m";
    end


    --- If print is nil, fallback to default value according to log level  TODO: add option to set up to which level logs are printed so we don't have a 'print_' value for every level
    if print == nil then

        if level == "verbose" then

            print = self.print_verbose;

        elseif level == "debug" then

            print = self.print_debug;

        else

            print = self.print;

        end
        
    end


    if print then

        -- Can't use this syntax here since we have to pass 'stream' as first parameter to stream.write and we can't infer this here by using a colon (:) 
        -- (write_func and write_func or stream.write)( message );

        if write_func then

            write_func( message );

        else

            stream:write( message );

        end

    end


    --- Only write to file if a path is present and the log level is anthing except 'verbose'.
    --- Alternatively, if log level is 'verbose', only write to file if Logger#print_verbose is set to true.
    -- TODO: why check for path? better check for file falsey and/or opening status
    if self.path and level ~= "verbose" or (level == "verbose" and self.print_verbose) then

        --- Write original '_message' here to avoid possibly writing debug level's color code in 'message' to file here
        self.file:write("[" .. utils.time.format() .. "] [" .. level .. "] " .. tostring(_message) .. "\n");

    end

end

--- Log given message at 'info' level, optionally force print to screen
function Logger:info(message, print)
    self:log("info", message, print);
end

--- Log given message at 'warn' level, optionally force print to screen
function Logger:warn(message, print)
    self:log("warn", message, print);
end

--- Log given message at 'error' level, optionally force print to screen
function Logger:error(message, print)
    self:log("error", message, print);
end

--- Log given message at 'debug' level, optionally force print to screen
function Logger:debug(message, print)
    self:log("debug", message, print);
end

--- Log given message at 'verbose' level, optionally force print to screen
function Logger:verbose(message, print)
    self:log("verbose", message, print);
end


--- Rotate log files. Note: By default, this closes the log file
function Logger:rotate(options)

    options = options or {};
    options.close = options.close ~= nil and options.close or true;


    if not component.isAvailable("data") then

        return false, "No data card available";

    end


    if options.close then

        self:close( { rotate = false } ); --- Flushes and closes the file, but avoids cyclic call of #rotate

    end


    local file_current_path = self.path;

    
    --- If current file is larger than 16,384 Bytes, compress it into archive and clear current file
    --- This technically checks for existance of a file at given path already, so we can use utils-file#_read
    if file_current_path ~= nil and (filesystem.size( file_current_path ) > 16384) then

        event.onError("[" .. self.name .. ":" .. file_current_path .. "] Rotating...");


        local data_current_compressed = component.data.deflate( utils_file._read( file_current_path ) );
        
        local file_compressed_identifier = tostring( utils.math.round( os.time() ) ); --- Unique time identifier

        local file_compressed_path = file_current_path:gsub("%.log", "_"..file_compressed_identifier..".log"); --- Replace '.log' suffix with '_$file_compressed_identifier.log'

        -- TODO: use proper utils_file#read implementation? only case could be an already existing path/timestamp since minecraft time is not necessarily consistent
        utils_file._write(file_compressed_path, data_current_compressed, _, true); --- Save compressed archived log file
        utils_file._write(file_current_path, ""); --- Clear original log file


        event.onError("[" .. self.name .. ":" .. file_current_path .. "] Rotating suceeded. " .. file_compressed_path);

        return true, file_compressed_path;
        
    end


    return false, file_current_path;

end

--- Transfer log file to Log-Server via the Log-Library
function Logger:transfer(options)

    options = options or {};

    options.name = options.name or self.name;
    options.path = options.path or self.path; --- This allows rotated files to be transfered as well


    self:flush();

    return log.transfer( options );

end

--- Flush buffer to file
function Logger:flush()

    if self.file then
        self.file:flush();
    end

end

--- Flushes, closes, rotates and releases log file (optionally disable flushing)
--- @param options table Options
--- @
function Logger:close(options)

    options = options or {};

    if options.flush == nil then options.flush = true end

    if options.rotate == nil then options.rotate = true end


    if options.flush then

        self:flush();

    end

    if options.rotate then

        --- Return here since any default call to #rotate will close the file already
        self:rotate();

    end


    return self.file and self.file:close() or true; -- TODO: return true even if we didn't explicitly closed the file (because it was closed/nil already)

end

--<< Class Methods end >>--




--- Return class object
return Logger;