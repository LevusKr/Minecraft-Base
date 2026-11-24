--- @module 'cluster/nas-library'
--[[
    NAS-Library
    This library provides functionality to communicate with the remote NAS-Server
--]]


-- Files and Configurations
--

-- Libraries and components
local component = require("component");
local constants = require("cluster/constants");
local Packet = require("cluster/network_packet");

local modem = component.modem;
--

-- Data tables
local nas = {};
-- 




--<< API Methods >>--

--- Operate at NAS-Server with given arguments and return Future object
--- @return table response_future Future object to be completed
--- @return boolean success Success of operation
--- @return string|table result Result of operation
--- 'response_future' is relevant for asynchronous operation (asnyc = true)
--- 'success' and 'result' are relevant for synchronous operation (asnyc = false)
function nas.operate(operation, file, options, async, timeout, content)

    local packet_request = Packet.create(
        modem.address,
        constants.name.nas,
        constants.port.file,
        constants.packet.data,
        {
            operation = operation or "info",
            file = file or ".nas-info",
            options = options or {},
            content = content
        }
    )

    --- Success of sending packet and optional error message
    local success, result = packet_request:send{open_port = true, encrypt = true};

    result = result or "NAS-Server unreachable"; --- If no error message is present, use default error message

    if not success then
        return _, success, result;
    end


    local response_future = packet_request:await_response(

        async,
        timeout

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

            response_future.result = {
                success = success,
                result = result
            }

        end
    );


    return response_future, success, result;

end

function nas.operate_(parameters)

    parameters = parameters or {};

    return nas.operate(
        parameters.operation,
        parameters.file,
        parameters.options,
        parameters.async,
        parameters.timeout,
        parameters.content
    );


end

--- Request file information
function nas.info(file, criteria, async, timeout)

    return nas.operate(
        "info",
        file,
        {
            criteria = criteria
        },
        async,
        timeout
    );

end

--- Request file opening
function nas.open(file, mode, async, timeout)

    return nas.operate(
        "open",
        file,
        {
            mode = mode
        },
        async,
        timeout
    );

end

--- Request file closure
function nas.close(file, async, timeout)

    return nas.operate(
        "close",
        file,
        _,
        async,
        timeout
    );

end

--- Request file content
function nas.read(file, count, keep_open, async, timeout)

    return nas.operate(
        "read",
        file,
        {
            count = count,
            keep_open = keep_open
        },
        async,
        timeout
    );

end

--- Request to write new file content (or optionally append to end of file)
function nas.write(file, content, append, keep_open, async, timeout)

    return nas.operate(
        "write",
        file,
        {
            append = append,
            keep_open = keep_open
        },
        async,
        timeout,
        content
    );

end

--- Request whether file exists
function nas.exists(file, async, timeout)

    return nas.operate(
        "exists",
        file,
        _,
        async,
        timeout
    );

end

--- Request whether file is a directory
function nas.is_directory(file, async, timeout)

    return nas.operate(
        "is_directory",
        file,
        _,
        async,
        timeout
    );

end

--- Request to create file
function nas.create(file, async, timeout)

    return nas.operate(
        "create",
        file,
        _,
        async,
        timeout
    );

end

--- Request to remove file
function nas.remove(file, async, timeout)

    return nas.operate(
        "remove",
        file,
        _,
        async,
        timeout
    );

end

--- Request to list path contents
function nas.list(file, async, timeout)

    return nas.operate(
        "list",
        file,
        _,
        async,
        timeout
    );

end

--- Request file size
function nas.size(file, async, timeout)

    return nas.operate(
        "size",
        file,
        _,
        async,
        timeout
    );

end

--- Request free space
function nas.space_free(async, timeout)

    return nas.operate(
        "space_free",
        _,
        _,
        async,
        timeout
    );

end

--- Request used space
function nas.space_used(async, timeout)

    return nas.operate(
        "space_used",
        _,
        _,
        async,
        timeout
    );

end

--- Request total space
function nas.space_total(async, timeout)

    return nas.operate(
        "space_total",
        _,
        _,
        async,
        timeout
    );

end

--- Request date of last modification
function nas.last_modified(file, async, timeout)

    return nas.operate(
        "last_modified",
        file,
        _,
        async,
        timeout
    );

end

--- Request file comparison and (optionally) download them altogether
function nas.compare(files, download, async, timeout, options)

    options = options or {};
    options.download = (download ~= nil) and download or options.download;

    return nas.operate(
        "compare",
        files,
        options,
        async,
        timeout
    );

end

--- Request remote file hashes without downloading file contents
function nas.hash(files, async, timeout)

    return nas.operate(
        "compare",
        files,
        {
            download    = false,
            hashes_only = true
        },
        async,
        timeout
    );

end

--<< API Methods end >>--




--- Return API Methods as table
return nas;