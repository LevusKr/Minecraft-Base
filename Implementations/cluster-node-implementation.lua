--[[
    Common Node-Implementation
    Common Node-Implementation component of network cluster structure
    A Node-Implementation acts as specification of an node, thus being internally connected to this node, which in turn is connected to the core
    and receiving (and displaying) general information, e.g. statuses of nodes
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-implementation.log"; -- TODO: create new file at every startup?
--

-- Libraries and components
local codec = require("cluster/codec");
local Config = require("cluster/config");
local constants = require("cluster/constants");
local dns = require("cluster/dns-library");
local _event = require("cluster/event");
local Future = require("cluster/future");
local Logger = require("cluster/logger");
local network = require("cluster/network");
local Packet = require("cluster/network_packet");

local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local term = require("term");
local thread = require("thread");
local utils = require("cluster/utils");

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

-- Data tables
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if packet_request.port ~= constants.port.main then return; end



    local client = packet_request.sender;
    local operation = packet_request.data.operation;
    local query = packet_request.data.query;

    logger:info("Client '" .. tostring( client ) .. "' requested '"  .. tostring( operation ) .. "' with '"  .. tostring( query ) ..  "'\n");



    local response = {
        success = false,
        result = "Server unreachable"
    };


    --- Send request to third party component, either directly or by a library
    local packet_request = Packet.create(
        modem.address,
        constants.name.core,
        constants.port.main,
        constants.packet.data,
        {
            operation = operation or "",
            query = query or ""
        }
    );

    packet_request:send( {open_port = true} );


    --- Receive third party's response and forward to client
    local response_future = packet_request:await_response(

        async,
        timeout

    );

    response_future:on_success(
        function(packet_response)
            
            response.success, response.result = packet_response.data.success, packet_response.data.result;

        end
    ):on_failure(
        function(error)

            response.result = error or response.result;

        end
    ):on_completion(
        function()

            local send_success, send_result = packet_request:send_response( response );

            if send_success then
                logger:info("Response to client '"  .. tostring( client ) ..  "': '" .. tostring( response.success ) .. " - " .. tostring( response.result ) .. "'\n");
            else
                logger:error("Response to client '"  .. tostring( client ) ..  "' couldn't be sent: " .. tostring( send_result ) .. "\n");
            end

        end
    );

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
            shutdown();
        end

    logger:info("Done.\n");
    --- Check for connection end



    --- Implement
    logger:info("Implement");

        --

    logger:info("Done.\n");
    --- Implement end

    
    
    --- Configure modem
    logger:info("Configuring modem...");

        modem.open( constants.port.main );
            logger:info("Modem port 'MAIN:" .. constants.port.main .. "' opened.\n");

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
end

--- Main shutdown function, executed once at shutdown
function shutdown()
    local time_shutdown = computer.uptime();
  

    logger:info("----- SHUTDOWN -----", false);
    logger:info("Shutting down...\n");



    --- Implement
    logger:info("Implement");

        --

    logger:info("Done.\n");
    --- Implement end



    --- Configure modem
    logger:info("Configuring modem...");

        modem.close( constants.port.main );
            logger:info("Modem port 'MAIN:" .. constants.port.main .. "' closed.");

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