--[[
    Log-Library
    This library provides functionality to communicate with the local log deamon (log-daemon.lua)
    by sending internal signals via event.push(...).
--]]


-- Files and Configurations
local PATH_LOG_REMOTE = "/var/log/cluster/";
--

-- Libraries and components
local constants = require("cluster/constants");
local Packet = require("cluster/network_packet");
local utils_file = require("cluster/utils-file");

local component = require("component");
local filesystem = require("filesystem");
--

-- Variables and Constants

--

-- Data tables
local log = {};
-- 




--<< API Methods >>--

--- Transfer log file to Log-Server
--- @param options table<string,string|boolean|number> Options {name,path,file,logs,append,async,timeout}
--- @param options.name string Name of logger
--- @param options.path string Path to log file
--- @param options.async? boolean Run asynchronously
--- @param options.timeout? number Timeout duration in seconds
function log.transfer(options)

    options = options or {};
    options.path = options.path or options.file;

    if options.name == nil then

        return false, "No name specified";

    end

    if options.path == nil and options.logs == nil then

        return false, "No path specified";

    end

    options.async = options.async ~= nil and options.async or false;
    options.timeout = options.timeout or 10;


    if not component.isAvailable("modem") then

        return false, "No modem available";

    end


    local logs_content = options.logs;

    if logs_content == nil then

        local success_read, result_read = utils_file.read(options.path, { binary = true });

        --- When reading the file failed, 'result_read' will be an error message
        if not success_read then

            return false, result_read;

        end

        logs_content = result_read;

    end

    if not logs_content or #logs_content == 0 then

        return true, "Empty log skipped";

    end


    local file_name = options.path and filesystem.name( options.path ) or (tostring( options.name ) .. ".log");


    local packet_request = Packet.create(
        component.modem.address,
        constants.name.log,
        constants.port.log,
        constants.packet.data,
        {
            operation = "store",
            name = options.name,
            file = file_name,
            append = options.append,
            logs = logs_content
        }
    );

    --- Success of sending packet and optional error message
    local success, result = packet_request:send({ open_port = true, encrypt = true });

    result = result or "Log-Server unreachable"; --- If no error message is present, use default error message

    if not success then

        if options.async then

            return _, success, result;

        end

        return false, result;

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

            result = error or result;

        end
    ):on_completion(
        function()

            --- Override future's 'packet_response' result with packet's actual payload result data, since that's what's important from now on
            response_future.result = {
                success = success,
                result = result
            };

        end
    );


    if options.async then

        return response_future;

    else

        --- Since the result has been awaited already and the handlers are also called immediately, no need to await here
        return success, result;

    end

end

--- Retrieve log file from Log-Server
--- @param options table<string,string|boolean|number> Options {name,path,file,async,timeout}
--- @param options.name string Name of logger
--- @param options.path string Path to log file
--- @param options.async? boolean Run asynchronously
--- @param options.timeout? number Timeout duration in seconds
function log.retrieve(options)

    options = options or {};
    options.path = options.path or options.file;

    if options.name == nil then

        return false, "No name specified";

    end

    if options.path == nil then

        return false, "No path specified";

    end

    options.async = options.async ~= nil and options.async or false;
    options.timeout = options.timeout or 10;


    if not component.isAvailable("modem") then

        return false, "No modem available";

    end


    local file_name = filesystem.name( options.path );


    local packet_request = Packet.create(
        component.modem.address,
        constants.name.log,
        constants.port.log,
        constants.packet.data,
        {
            operation = "retrieve",
            name = options.name,
            file = file_name
        }
    );

    --- Success of sending packet and optional error message
    local success, result = packet_request:send({ open_port = true, encrypt = true });

    result = result or "Log-Server unreachable"; --- If no error message is present, use default error message

    if not success then

        if options.async then

            return _, success, result;

        end

        return false, result;

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

            result = error or result;

        end
    ):on_completion(
        function()

            --- Override future's 'packet_response' result with packet's actual payload result data, since that's what's important from now on
            response_future.result = {
                success = success,
                result = result
            };

        end
    );


    if options.async then

        return response_future;

    else

        --- Since the result has been awaited already and the handlers are also called immediately, no need to await here
        return success, result;

    end

end

--<< API Methods end >>--




return log;