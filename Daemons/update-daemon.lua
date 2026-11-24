--[[
    Update-Daemon
    This Update-Daemon will run on startup and check the update server for updates
    If there are new updates available, it will either download and install them and reboot
    OR only notify the user for manually updating and proceed with startup.
--]]


-- Libraries and components
local codec = require("cluster/codec");
local update = require("cluster/update-library");
local utils_string = require("cluster/utils-string");

local os = require("os");
local term = require("term");

local cwrite = utils_string.cwrite;
--

-- Variables and Constants
local download = false; --- If daemon should only request update availability (false) or to download new content directly (true)
local async = false;    --- Whether daemon should perform request sync or asynchronous
local timeout = 10;     --- Timeout after which request is cancelled
local direct = true;    --- Whether NAS-Server should transfer file data directly to this client
local delta = true;     --- Whether incremental chunk-level deltas should be used where possible
local force = false;    --- Whether to force re-downloading all files regardless of checksum equality
local reboot = false;   --- Whether to automatically reboot if updates were installed
--

-- Data tables
local options_default = {
    download = download,
    async    = async,
    timeout  = timeout,
    direct   = direct,
    delta    = delta,
    force    = force,
    reboot   = reboot,
    write    = true,
    verbose  = false
};
options_default.__index = options_default;
--




--<< Helper Functions >>--

local function normalize_options(options)

    if type( options ) == "string" then
        options = codec.decode( options );
    end

    if type( options ) ~= "table" then
        options = {};
    end


    return setmetatable(options, options_default);

end

--<< Helper Functions end >>--




--<< Daemon Functions >>--

--- Perform update check or download via update-library
function _update(options)

    options = normalize_options( options );

    local response_future = update.operate(
        options.download and "download" or "check",
        options
    );

    response_future:on_completion(
        function()

            local details = response_future.result or {};

            cwrite(options.write, (details.success and "Success" or "Failure") .. " - " .. tostring( details.result ) .. "\n");

            if not options.async then
                os.sleep( 1 );
            end

        end
    );


    return response_future, response_future.result and response_future.result.success, response_future.result and response_future.result.result;

end

--<< Daemon Functions end >>--




--<< RC Handling >>--

--- RC API start function - Query Update-Server for updates on startup
function start(options)

    options = normalize_options( options );

    cwrite(options.write, "Update-Daemon starting...\n");

    return _update( options );

end

--- RC API stop function - Clear cached state
function stop()

    update.available = {};
    update.last_result = nil;

end

--- RC API status function - Print last update check/install status
function status()

    local last = update.last_result;

    if not last then

        term.write("Update-Daemon: No update operation has been executed in this session.\n");
        return true, update.available;

    end

    term.write("Last status: " .. (last.success and "Success" or "Failure") .. " - " .. tostring( last.result ) .. "\n");

    if update.available and #update.available > 0 then

        term.write("Available updates (" .. tostring( #update.available ) .. "):\n");

        for _, file in ipairs( update.available ) do
            term.write("  - " .. tostring( file ) .. "\n");
        end

    end


    return last.success, last;

end

--<< RC Handling >>--
