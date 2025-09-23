--[[
    Update-Server
    Update-Server component of network cluster structure
    A Update-Server acts as distributor of file updates, thus responding to update checks
    with file contents for those files, or optionally if an update is possible.
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-update.log"; -- TODO: create new file at every startup?
--

-- Libraries and components
local codec = require("cluster/codec");
local Config = require("cluster/config");
local constants = require("cluster/constants");
local _event = require("cluster/event");
local Future = require("cluster/future");
local Logger = require("cluster/logger");
local nas = require("cluster/nas-library");
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

local running = false;
local timer_loop = 0;
local thread_interrupt_handler = nil;
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
function data_handle(_, _packet_request)

    local data_handle_success, data_handle_result = pcall(
        function(_packet_request)



            local packet_request = Packet:decode( _packet_request );
            if packet_request.port ~= constants.port.update then return; end



            local client = packet_request.sender;
            local operation = packet_request.data.operation;
            local files = packet_request.data.files; -- files to check {"file_name"="h7ugtfe", ...}
            local files_count = packet_request.data.files_count;
            local download = operation == "download";

            logger:info("Client '" .. tostring( client ) .. "' requested '" .. tostring( operation ) .. "' for ".. tostring( files_count ) .. " files. Contacting NAS-Server..."); -- TODO: fix files count



            local response = {
                success = false,
                result = "NAS-Server unreachable"
            };

            
            local response_future, success, result = nas.compare(

                files,
                download,
                true, -- async
                10 -- timeout

            );

            if response_future == nil and not success then
                logger:warn(tostring(result));
                return;
            end

            response_future:on_success(
                function(packet_response)

                    response.success, response.result = packet_response.data.success, packet_response.data.result; -- {"file_name"=true/false, ...} OR {"file_name"=*file content*} (depends on download flag)

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



        end,
        _packet_request
    )

    if not data_handle_success then

        logger:error("Error while handling data request packet: " .. tostring( data_handle_result ));

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