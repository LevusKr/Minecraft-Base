--[[
    Log-Server
    Log-Server component of network cluster structure
    The Log-Server acts as central logger for the cluster, thus accepting requests
    for storing and serving log files on/from the network's nas.
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-log.log"; -- TODO: create new file at every startup?

local path_logs = "/var/log/cluster/";
--

-- Libraries and components
local codec = require("cluster/codec");
local constants = require("cluster/constants");
local dns = require("cluster/dns-library");
local Logger = require("cluster/logger");
local nas = require("cluster/nas-library");
local Packet = require("cluster/network_packet");
local utils = require("cluster/utils");
local utils_file = require("cluster/utils-file");
local utils_string = require("cluster/utils-string");

local component = require("component");
local computer = require("computer");
local event = require("event");
local filesystem = require("filesystem");
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

local timer_loop = 0;
local thread_interrupt_handler = nil;
--




--<< Helper Functions >>--

--- Resolves remote NAS path for given logger name and log file path/name
local function resolve_log_path(name, file)

    local file_name = filesystem.name( tostring( file or "unknown.log" ) );
    local dir_node = utils_file.join_path(path_logs, tostring( name or "unknown" ));

    return utils_file.join_path(dir_node, file_name);

end

--<< Helper Functions end >>--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data'event
function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if not packet_request or packet_request.port ~= constants.port.log then return; end



    -- TODO: handle invalid operations, parameters etc. across server-client architectures in codebase
    -- TODO: also do not just assume some default values since the client may be expecting a whole different process and return values
    local client_address = packet_request.sender;
    local client = client_address;
    local operation = packet_request.data.operation or "store";
    local name = packet_request.data.name or "unknown";
    local file = packet_request.data.file or "unknown";
    local append = packet_request.data.append or false;
    local logs = packet_request.data.logs or "";

    local dns_success, dns_result = dns.lookup( client_address );

    if dns_success and dns_result then
        client = dns_result;
    end

    local path_remote = resolve_log_path(name, file);
    local logs_preview = tostring( utils_string.dotate(logs, 32) ):gsub("\r", ""):gsub("\n", "\\n");

    logger:info("Client '" .. tostring( client ) ..
        "' requested operation '" .. tostring( operation ) ..
        "' on logger '" .. tostring( name ) ..
        "' at log file '" .. tostring( path_remote ) ..
        "' with " .. utils.math.adjust_value(#logs, "B") .. " of data" ..
        ": '" .. logs_preview .. "'"
    );



    local response = {
        success = false,
        result = "Undefined"
    };



    local function handler_success(packet_response)

        response.success, response.result = packet_response.data.success, packet_response.data.result;

    end

    local function handler_failure(message)

        response.success = false;
        response.result = message or response.result;

    end

    local function handler_completion()

        local send_success, send_result = packet_request:send_response( response );

        if send_success then

            logger:info("Response to client '" .. tostring( client ) .. "': '" .. tostring( response.success ) .. " - " .. tostring( utils_string.dotate(codec.encode( response.result ), 100) ) .. "'\n");

        else

            logger:error("Response to client '" .. tostring( client ) .. "' couldn't be sent: " .. tostring( send_result ) .. "\n");

        end

    end



    if operation == "store" then

        local future_write, success_send, result_send = nas.operate(
            "write",
            path_remote,
            {
                append = append,
                keep_open = false,
                binary = true
            },
            true, --- async
            10,   --- timeout
            logs
        );

        if not future_write then

            handler_failure( result_send or "Failed to contact NAS-Server" );
            handler_completion();

            return;

        end

        future_write:on_success( handler_success )
            :on_failure( handler_failure )
            :on_completion( handler_completion );

    elseif operation == "retrieve" then

        local future_read, success_send, result_send = nas.operate(
            "read",
            path_remote,
            {
                count = "*a",
                keep_open = false,
                binary = true
            },
            true, --- async
            10    --- timeout
        );

        if not future_read then

            handler_failure( result_send or "Failed to contact NAS-Server" );
            handler_completion();

            return;

        end

        future_read:on_success( handler_success )
            :on_failure( handler_failure )
            :on_completion( handler_completion );

    else

        handler_failure("Invalid operation: " .. tostring( operation ));
        handler_completion();

    end

end

--- Sends internal data to Core, passed through by Common Node via internal_data event
function data_send(data)

    event.push("internal_data", data); -- TODO: data size and type etc.

end

--<< Data Handling end >>--




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
            -- shutdown();
        end

    logger:info("Done.\n");
    --- Check for connection end



    --- Configure modem
    logger:info("Configuring modem...");

        modem.open( constants.port.log );
            logger:info("Modem port 'LOG:" .. constants.port.log .. "' opened.");

    logger:info("Done.\n");
    --- Configure modem end



    --- Register event handlers
    logger:info("Registering event handlers...");

        local error_handler_event = function(name, event_listener)

            return name, function()
                xpcall(
                    event_listener,
                    function(success, result)

                        if not success then
                            logger:error("Error in event handler '" .. name .. "': " .. tostring( result ));
                        end

                    end
                );

            end

        end

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
end

--- Main shutdown function, executed once at shutdown
function shutdown()
    local time_shutdown = computer.uptime();


    logger:info("----- SHUTDOWN -----", false);
    logger:info("Shutting down...\n");



    --- Configure modem
    logger:info("Configuring modem...");

        modem.close( constants.port.log );
            logger:info("Modem port 'LOG:" .. constants.port.log .. "' closed.");

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
    --logger:transfer();
    running = false;

    os.exit(0);


    -- TODO: tell common node to disconnect?
end

--<< Main Functions end >>--




startup();

local success, result = thread.waitForAny({thread_interrupt_handler});

shutdown();