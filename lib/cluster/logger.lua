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
--- @field path_rotated string|nil
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
    path_rotated = nil,
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
--- @param name string
--- @param path string
---
--- @param print boolean? Default: true
--- @param print_debug boolean? Default: false
--- @param print_verbose boolean? Default: false
---
--- @param buffer_enable boolean? Default: true
--- @param buffer_size number? Default: constants.buffer.log
---
--- @return boolean success, Logger|string?
function Logger.create(name, path, print, print_debug, print_verbose, buffer_enable, buffer_size)

    local logger = setmetatable({
        name = name,
        path = path,
        path_rotated = nil,
        print = print ~= nil and print or true,
        print_debug = print_debug or false,
        print_verbose = print_verbose or false,
        buffer_enable = buffer_enable ~= nil and buffer_enable or true,
        buffer_size = buffer_size or constants.buffer.log
    }, Logger);


    local success_open, error_open = logger:open();

    if not success_open then

        return false, error_open;

    end


    return true, logger;

end

--- Opens (or re-opens) the underlying log file handle and configures buffering
function Logger:open()

    if self.file then

        return true;

    end

    if not self.path then

        return false, "No log file path specified";

    end


    filesystem.makeDirectory( filesystem.path( self.path ) );

    local file, file_error = io.open(self.path, "a");

    if not file then

        return false, file_error;

    end


    self.file = file;
    self.file:setvbuf(self.buffer_enable and "full" or "no", self.buffer_size or constants.buffer.log);


    return true;

end

--- Multi-purpose equivalent of event#onError. Writes given 'message' into file at '/tmp/${name}'
function Logger.temporary(name, message)

    local file = io.open("/tmp/" .. tostring( name ) .. ".log", "a");

    if file then

        pcall(file.write, file, tostring( message ), "\n");
        file:close();

    end

end

--- Log given message at given level, optionally print to screen
--- @param level LogLevel
--- @param _message string
--- @param print boolean?
--- @param write_func function?
function Logger:log(level, _message, print, write_func)

    local stream = io.stdout;

    if level == constants.log.error then

        stream = io.stderr;

    elseif level == constants.log.warn then

        ---@diagnostic disable-next-line: undefined-field
        stream = io.stdwrn or io.stdout;

    end


    local message = "[" .. utils.time.format() .. "] [" .. level .. "] " .. tostring( _message ) .. "\n";

    --- Color debug logs magenta
    if level == constants.log.debug then

        message = "\27[35m" .. message .. "\27[37m";

    end


    --- If print is nil, fallback to default value according to log level  TODO: add option to set up to which level logs are printed so we don't have a 'print_' value for every level
    if print == nil then

        if level == constants.log.verbose then

            print = self.print_verbose;

        elseif level == constants.log.debug then

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


    --- Only write to file if a path is present and the log level is anything except 'verbose'.
    --- Alternatively, if log level is 'verbose', only write to file if Logger#print_verbose is set to true.
    if (level ~= constants.log.verbose or self.print_verbose) and self.path then

        if not self.file then

            self:open();

        end

        if self.file then

            --- Write original '_message' here to avoid possibly writing debug level's color code in 'message' to file here
            self.file:write("[" .. utils.time.format() .. "] [" .. level .. "] " .. tostring( _message ) .. "\n");

        end

    end

end

--- Log given message at 'info' level, optionally force print to screen
--- @param message string
--- @param print boolean?
function Logger:info(message, print)
    self:log(constants.log.info, message, print);
end

--- Log given message at 'warn' level, optionally force print to screen
--- @param message string
--- @param print boolean?
function Logger:warn(message, print)
    self:log(constants.log.warn, message, print);
end

--- Log given message at 'error' level, optionally force print to screen
--- @param message string
--- @param print boolean?
function Logger:error(message, print)
    self:log(constants.log.error, message, print);
end

--- Log given message at 'debug' level, optionally force print to screen
--- @param message string
--- @param print boolean?
function Logger:debug(message, print)
    self:log(constants.log.debug, message, print);
end

--- Log given message at 'verbose' level, optionally force print to screen
--- @param message string
--- @param print boolean?
function Logger:verbose(message, print)
    self:log(constants.log.verbose, message, print);
end

--- Flush buffer to file
function Logger:flush()

    if self.file then

        self.file:flush();

    end

end

--- Flushes, closes, rotates and releases log file (optionally disable flushing or trigger transfer)
--- @param options table? Options {flush,rotate,transfer}
function Logger:close(options)

    options = options or {};

    if options.flush == nil then options.flush = true; end

    if options.rotate == nil then options.rotate = true; end


    if options.flush then

        self:flush();

    end

    if self.file then

        self.file:close();
        self.file = nil;

    end


    local success_rotate, result_rotate = false, self.path;

    if options.rotate then

        success_rotate, result_rotate = self:rotate({ close = false });

    end


    if options.transfer then

        return self:transfer({ path = result_rotate });

    end


    return true, result_rotate;

end

--- Rotate log files. Note: By default, this closes the log file
function Logger:rotate(options)

    options = options or {};
    options.close = options.close ~= nil and options.close or true;


    if options.close then

        self:close({ rotate = false }); --- Flushes and closes the file, but avoids cyclic call of #rotate

    end


    local file_current_path = self.path;


    --- If current file is larger than 16,384 Bytes, compress it into archive (if data card is available) and clear current file
    if file_current_path ~= nil and filesystem.exists( file_current_path ) and (filesystem.size( file_current_path ) > 16384) then

        local success_read, data_current = utils_file.read(file_current_path, { binary = true });

        if not success_read then

            return false, "Failed to read log file for rotation: " .. tostring( data_current );

        end


        local data_archived = data_current;

        if component.isAvailable("data") then

            data_archived = component.data.deflate( data_current );

        end


        local file_compressed_identifier = tostring( utils.math.round( os.time() ) ); --- Unique time identifier

        local file_compressed_path = file_current_path:gsub("%.log$", "_" .. file_compressed_identifier .. ".log"); --- Replace '.log' suffix with '_$file_compressed_identifier.log'


        utils_file.write(file_compressed_path, data_archived, { binary = true }); --- Save compressed archived log file
        utils_file.write(file_current_path, "");                                  --- Clear original log file

        self.path_rotated = file_compressed_path;


        return true, file_compressed_path;

    end


    return false, file_current_path;

end

--- Transfer log file to Log-Server via the Log-Library
function Logger:transfer(options)

    options = options or {};

    local path_target = options.path or options.file or self.path_rotated or self.path;
    self.path_rotated = nil;

    options.name = options.name or self.name;
    options.path = path_target; --- This allows rotated files to be transfered as well


    self:flush();

    return log.transfer( options );

end

--<< Class Methods end >>--




--- Return class object
return Logger;
