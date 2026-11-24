--[[
    Update-Server
    Update-Server component of network cluster structure
    A Update-Server acts as distributor and coordinator of file updates, responding to update checks
    and coordinating direct or tunneled file/delta transfers from the NAS-Server.
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-update.log"; -- TODO: create new file at every startup?
--

-- Libraries and components
local codec = require("cluster/codec");
local constants = require("cluster/constants");
local dns = require("cluster/dns-library");
local Logger = require("cluster/logger");
local nas = require("cluster/nas-library");
local Packet = require("cluster/network_packet");
local Stats = require("cluster/stats");
local utils = require("cluster/utils");
local utils_string = require("cluster/utils-string");

local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local term = require("term");
local thread = require("thread");


local modem = component.modem;
--

-- Variables and constants
local logger = nil;
local log_print = true;
local log_debug = true;
local log_verbose = true;
local log_buffer = true;

local hostname = nil;

local running = false;
local timer_loop = 0;
local thread_interrupt_handler = nil;

local timeout_default = 10; --- Default timeout for NAS requests if none is provided in options
--

-- Data tables
local operations = {}; --- Convenience table holding operations applicable to Update-Server requests

local stats = Stats.create("node-update");
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
function data_handle(_, _packet_request)

    local data_handle_success, data_handle_result = pcall(
        function(_packet_request)

            local packet_request = Packet:decode( _packet_request );
            if packet_request.port ~= constants.port.update then return; end



            local client_address = packet_request.sender;
            local client = client_address;
            local operation = packet_request.data.operation or "check";
            local files = packet_request.data.files or {};
            local files_count = packet_request.data.files_count or 0;
            local options = packet_request.data.options or {};

            if files_count == 0 and type( files ) == "table" then

                for _ in pairs( files ) do
                    files_count = files_count + 1;
                end

            end


            local dns_success, dns_result = dns.lookup( client_address );

            if dns_success and dns_result then
                client = dns_result;
            end


            logger:info("Client '" .. tostring( client ) ..
                "' requested '" .. tostring( operation ) ..
                "' for " .. tostring( files_count ) ..
                " files with options '" .. codec.encode( options ) .. "'."
            );

            stats:record_request(client, operation, #_packet_request);

            if type( files ) == "table" then

                for entry_file in pairs( files ) do
                    if type( entry_file ) == "string" then
                        stats:record_detail("file", entry_file);
                    end
                end

            end


            if operations[ operation ] then

                operations[ operation ](files, files_count, options, packet_request, client, client_address);

            else

                local response = {
                    success = false,
                    result  = "Unsupported operation: " .. tostring( operation )
                };

                local packet_response = packet_request:create_response( response );
                local send_success, send_result = packet_response:send();

                if send_success then
                    stats:record_response(false, packet_response:size());
                else
                    stats:record_error(client, operation, send_result);
                end

            end

        end,
        _packet_request
    );

    if not data_handle_success then

        logger:error("Error while handling data request packet: " .. tostring( data_handle_result ));

    end

end

--- Sends internal data to Core, passed through by Common Node via internal_data event
function data_send(data)

    event.push("internal_data", data); -- TODO: data size and type etc.

end

--<< Data Handling end >>--




--<< Node Functions >>--

--- Export server statistics
function operations.stats(_, _, _, packet_request, client)

    local response = {
        success = true,
        result  = stats:export()
    };

    local packet_response = packet_request:create_response( response );
    local send_success, send_result = packet_response:send();

    if send_success then
        logger:info("Sent stats to client '" .. tostring( client ) .. "'.\n");
        stats:record_response(true, packet_response:size());
    else
        logger:error("Stats response to client '" .. tostring( client ) .. "' couldn't be sent: " .. tostring( send_result ) .. "\n");
        stats:record_error(client, "stats", send_result);
    end

end

--- Invalidate file hash and chunk cache on NAS-Server
function operations.invalidate(_, _, options, packet_request, client)

    options = options or {};

    local response = {
        success = false,
        result  = "NAS-Server unreachable"
    };

    local response_future, success, result = nas.compare(
        {},
        false,
        true,
        options.timeout or timeout_default,
        {
            invalidate = true
        }
    );

    if response_future == nil and not success then

        logger:warn( tostring( result ) );
        packet_request:send_response( response );
        stats:record_error(client, "invalidate", result);
        return;

    end

    response_future:on_success(
        function(packet_response)

            response.success = packet_response.data.success;
            response.result = "Update and NAS caches invalidated";

        end
    ):on_failure(
        function(error)

            response.result = error or response.result;

        end
    ):on_completion(
        function()

            local packet_response = packet_request:create_response( response );
            local send_success, send_result = packet_response:send();

            if send_success then
                logger:info("Cache invalidation response to client '" .. tostring( client ) .. "': '" .. tostring( response.success ) .. " - " .. tostring( response.result ) .. "'\n");
                stats:record_response(response.success, packet_response:size());
            else
                logger:error("Cache invalidation response to client '" .. tostring( client ) .. "' couldn't be sent: " .. tostring( send_result ) .. "\n");
                stats:record_error(client, "invalidate", send_result);
            end

        end
    );

end

--- Compare client file hashes with NAS-Server and optionally coordinate direct or tunneled file/delta transfer
local function handle_compare_or_download(download, files, files_count, options, packet_request, client, client_address)

    options = options or {};

    local operation_name = download and "download" or "check";
    local use_direct = download and (options.direct ~= false);
    local use_delta = (options.delta == nil) and true or options.delta;
    local use_force = options.force or false;
    local timeout = options.timeout or timeout_default;

    local response = {
        success = false,
        result  = "NAS-Server unreachable"
    };

    local nas_options = {
        download  = download,
        delta     = use_delta,
        force     = use_force,
        timeout   = timeout,
        recipient = use_direct and {
            name    = client,
            address = client_address,
            port    = packet_request.port,
            id      = packet_request.id
        } or nil
    };

    local forwarded_directly = false;

    local response_future, success, result = nas.compare(
        files,
        download,
        true,
        timeout,
        nas_options
    );

    if response_future == nil and not success then

        logger:warn( tostring( result ) );

        response.result = result or response.result;
        local packet_response = packet_request:create_response( response );
        packet_response:send();

        stats:record_error(client, operation_name, response.result);
        return;

    end

    response_future:on_success(
        function(packet_response)

            local nas_data = packet_response.data or {};
            local nas_result = nas_data.result;

            if nas_data.success and type( nas_result ) == "table" and nas_result.forwarded then

                forwarded_directly = true;
                response.success = true;
                response.result = nas_result.summary;

            else

                response.success = nas_data.success;
                response.result = nas_result;

            end

        end
    ):on_failure(
        function(error)

            response.result = error or response.result;

        end
    ):on_completion(
        function()

            --- If NAS-Server already delivered the payload directly to the client, only log & record stats here
            if forwarded_directly then

                local summary = response.result or {};

                logger:info("NAS-Server directly delivered updates to client '" .. tostring( client ) ..
                    "' (checked: " .. tostring( summary.total or files_count ) ..
                    ", updated: " .. tostring( summary.updated or 0 ) ..
                    ", delta: " .. tostring( summary.delta or 0 ) ..
                    ", saved: " .. utils.math.adjust_value(summary.saved or 0, "B") .. ").\n"
                );

                stats:record_response(true, 0);
                return;

            end


            local packet_response = packet_request:create_response( response );
            local send_success, send_result = packet_response:send();

            if send_success then

                logger:info("Response to client '" .. tostring( client ) .. "': '" .. tostring( response.success ) .. " - " .. tostring( utils_string.dotate(codec.encode( response.result ), 100) ) .. "'\n");

                stats:record_response(response.success, packet_response:size());

            else

                logger:error("Response to client '" .. tostring( client ) .. "' couldn't be sent: " .. tostring( send_result ) .. "\n");

                stats:record_error(client, operation_name, send_result);

            end

        end
    );

end

--- Check file equality against NAS-Server
function operations.check(files, files_count, options, packet_request, client, client_address)

    handle_compare_or_download(false, files, files_count, options, packet_request, client, client_address);

end

--- Coordinate file/delta download from NAS-Server
function operations.download(files, files_count, options, packet_request, client, client_address)

    handle_compare_or_download(true, files, files_count, options, packet_request, client, client_address);

end

--<< Node Functions end >>--




--<< Threads >>-

--- Handle program interruption. Every task depends on boolean 'running', so when running is false they automatically clean up and exit
local function interrupt_handler()

    while running do

        event.pull("interrupted");
        running = false;

    end

end

--<< Threads end >>--




--<< Main Functions >>--

--- Initialize logger
local function init_log()

    local logger_init_success, logger_init_result = Logger.create(
        hostname,
        file_log,
        log_print,
        log_debug,
        log_verbose,
        log_buffer
    );


    if not logger_init_success then

        error("Error whilst initializing logger: " .. tostring( logger_init_result ));

    end


    logger = logger_init_result;

end

--- Main loop function, executed once every second
function loop()

    --

end

--- Main startup function, executed once at startup
function startup()

    local time_startup = computer.uptime();


    running = true;

    hostname = utils.internal.hostname();

    init_log();



    term.clear();
    logger:info("----- STARTUP -----", false);
    logger:info("Starting up...\n");



    --- Check for connection
    logger:info("Checking for connection to Core...");

        if not os.getenv( constants.env.connected ) then
            logger:error("Not connected to Core.");
            shutdown();
        end

    logger:info("Done.\n");
    --- Check for connection end



    --- Configure modem
    logger:info("Configuring modem...");

        modem.open( constants.port.update );
            logger:info("Modem port 'UPDATE:" .. constants.port.update .. "' opened.\n");

    logger:info("Done.\n");
    --- Configure modem end



    --- Register event handlers
    logger:info("Registering event handlers...");

        event.listen("cluster_data", data_handle);
            logger:info("Listener 'cluster_data' registered.");

    logger:info("Done.\n");
    --- Register event handlers end



    --- Start loop
    logger:info("Starting loop...");

        timer_loop = event.timer(1, loop, math.huge);

    logger:info("Done.\n");



    --- Start threads
    logger:info("Starting threads...");

        thread_interrupt_handler = thread.create(interrupt_handler);
            logger:info("Thread 'interrupt_handler' started.");

    logger:info("Done.\n ");
    --- Start threads end



    local time_startup_finished = computer.uptime() - time_startup;
    logger:info("Successfully started up in " .. time_startup_finished .. " seconds.\n\n");




    --- When updating manually via /bin/update.lua cli, /home/cluster-node-nas.lua won't be running so the update server won't reach cluster-node-nas, thus leading to manual updating failing
    --- So we disabled update at startup and rather update after startup of /home/cluster-node-nas.lua (this program)
    --os.execute("update true");
    
end

--- Main shutdown function, executed once at shutdown
function shutdown()
    local time_shutdown = computer.uptime();
  

    logger:info("----- SHUTDOWN -----", false);
    logger:info("Shutting down...\n");



    --- Configure modem
    logger:info("Configuring modem...");

        modem.close( constants.port.update );
            logger:info("Modem port 'UPDATE:" .. constants.port.update .. "' closed.");

    logger:info("Done.\n");
    --- Configure modem end



    --- Unregister event handlers
    logger:info("Unregistering event handlers...");

        event.ignore("cluster_data", data_handle);
            logger:info("Listener 'cluster_data' unregistered.");

    logger:info("Done.\n");
    --- Unregister event handlers end



    --- Stop loop
    logger:info("Stopping loop...");

        event.cancel(timer_loop);

    logger:info("Done.\n");
    --- Stop loop end



    local time_shutdown_finished = computer.uptime() - time_shutdown;
    logger:info("Successfully shut down in " .. time_shutdown_finished .. " seconds.");




    logger:close();
    logger:transfer();
    running = false;

    os.exit(0);


    -- TODO: tell common node to disconnect?
end

--<< Main Functions end >>--




startup();

local success, result = thread.waitForAny({thread_interrupt_handler});

shutdown();
