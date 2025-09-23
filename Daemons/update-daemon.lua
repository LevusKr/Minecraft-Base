--[[
    Update-Daemon
    This Update-Daemon will run on startup and check the update server for updates
    If there are new updates available, it will either download and install them and reboot
    OR only notify the user for manually updating and proceed with startup.
--]]


-- Files and configurations
local file_updates = "/etc/updates.cfg"; --- List of updateable files
--

-- Libraries and components
local codec = require("cluster/codec");
local Config = require("cluster/config");
local constants = require("cluster/constants");
local update = require("cluster/update-library");
local Packet = require("cluster/network_packet");
local utils = require("cluster/utils");
local utils_file = require("cluster/utils-file");

local component = require("component");
local os = require("os");
local term = require("term");
local event = require("event");


local modem = component.modem;
local data = component.data;
--

-- Variables and Constants
local download = false; --- If daemon should only request update availability (false) or to download new content directly (true)
local async = false; --- Whether daemon should perform request sync or asynchronous
local timeout = 10; --- Timeout after which request is cancelled
--

-- Data tables
local config_updates = Config:create( file_updates );

local updates_available = {}; --- Available updates, only used if 'download' is false (see above)
--




--<< Daemon Functions >>--

--- Check for available updates
function _update(options)

    if type( options ) == "string" then
        options = codec.decode( options );
    end

    options = options or {
        download = download,
        async = async,
        timeout = timeout
    };




    term.write("Checking for updateable files... "..tostring(download).."\n");

    local success_hash_local, file_hashes, file_hashes_count = update.hash_local({reload = true});

    --- If updates file could not be loaded, exit
    if not success_hash_local then

        --- 'file_hashes' will be an error message  TODO: refactor variable name
        term.write("Error: " .. tostring( file_hashes ));

        os.sleep( 2 );


        return false, file_hashes;

    elseif file_hashes_count == 0 then --- If no files to update, return and exit here

        term.write("No files to update-check. Proceed\n");

        os.sleep( 2 );

        return true, "No files to update-check";

    end



    term.write("Contacting update server with " .. tostring( file_hashes_count ) .. " files... Timeout after " .. tostring( options.timeout ) .. " seconds\n\n");


    local response_future, success, result = update.operate(
        options.download and "download" or "check",
        file_hashes,
        file_hashes_count,
        {
            write = true,
            async = options.async,
            timeout = options.timeout
        }
    );


    response_future:on_completion(
        function()

            term.write(( success and "Success" or "Failure" ) .. " - " .. tostring( result ) .. "\n")

            os.sleep( 2 );

        end
    );



    return response_future;
    
end

--<< Daemon Functions end >>--




--<< RC Handling >>--

--- RC API start function - Query Update-Server for updates
function start(options)

    options = options or {};

    options = {
        download = (options.download == nil) and download or options.download,
        async    = (options.async    == nil) and async    or options.async,
        timeout  = (options.timeout  == nil) and timeout  or options.timeout,
    };

    return _update( options );

end

--- RC API stop function - XXX
function stop()

    -- TODO: implement
    
end

--<< RC Handling >>--