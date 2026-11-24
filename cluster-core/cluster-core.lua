--[[
    Cluster-Core
    Main component of network cluster structure
    The Core acts as central head of the network, thus having active connections
    to every registered Node and monitoring their activity.
--]]


-- Files and Configurations
--

-- Libraries and Components
local shared_data = require("cluster/core/core-shared_data");
local packet_handling = require("cluster/core/core-packet_handling");
local node_handling = require("cluster/core/core-node_handling");
local core_command_handling = require("cluster/core/core-command_handling");

local codec = require("cluster/codec");
local constants = require("cluster/constants");
local Logger = require("cluster/logger");
local Packet = require("cluster/network_packet");
local Terminal = require("cluster/terminal");

local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local thread = require("thread");


local modem = component.modem;
--

-- Variables and constants
local logger = shared_data.logger;


local timer_loop = 0;
local thread_interrupt_handler = nil;

local thread_packet_processor = nil;
local packet_processor_interval = 0.2; --- Seconds between runs

local thread_alive_processor = nil;
local alive_processor_interval = 0.2; --- Seconds between runs
--

-- Data tables
local packet_handler = packet_handling.packet_handler; --- Packet handlers for packet types (e.g. packet_handler.HANDSHAKE for handshake packets)
--





--<< Threads >>-

--- Handle program interruption. Every task depends on boolean 'running', so when running is false they clean up and exit
local function interrupt_handler()

    while shared_data.running do

        event.pull("interrupted");

        shared_data.update_var_running(false);

    end

end

--- Get current packet in queue and call corresponding packet handler   TODO: refactor because handle_packet won't ever fail
local function packet_processor()

    local packet = nil;
    local attempts = 0;

    while shared_data.running do
        
        ---@diagnostic disable-next-line: undefined-field
        os.sleep(packet_processor_interval);

        -- logger:debug("Packet queue: " .. tostring(codec.encode(shared_data.packet_queue)));

        --- If packet available, pull it
        if not packet and next(shared_data.packet_queue) then
            packet = shared_data.packet_queue[1];
        end


        if packet then

            --- xpcall signature
            local success, result = packet_handler.generic( packet );

            if not success then
                logger:error("Incoming packet '" .. tostring( packet.id ) .. "' raised an error: " .. tostring( result ));
            end


            --- If either attempts ran out or packet was successfully handled -> remove from queue
            if attempts > 5 or success then

                logger:verbose("Incoming packet '" .. tostring( packet.id ) .. "' removed from queue.");
                table.remove(shared_data.packet_queue, 1);

                packet = nil;
                attempts = 0;

            else
                attempts = attempts + 1;
            end

        end

    end

end

--- Iterate over nodes and refresh connection, status and ttl (i.e. check if node is dead)
local function alive_processor()
    while shared_data.running do
        ---@diagnostic disable-next-line: undefined-field
        os.sleep(alive_processor_interval);

        for _, node in pairs(shared_data.nodes.contents) do
            local address = node.address;
            local name = node.name;
            local connected = node.connected;
            local status = node.status;
            local ttl = node.ttl;

            --- If node is connected but stopped sending alive packets (status is true but ttl is reached), send alive packet and set node's status to inactive
            if connected and status and (ttl < computer.uptime()) then
                node:alive({ packet_only = true }); --- Send alive packet to possibly 'wake-up' node.

                node.status = false;
                --node:inactive();


                logger:info("Node '" .. name .. "' didn't respond in time. Sent alive packet.");


                -- TODO: "deactivation" is ambigious
                packet_handling.send_packet_event(
                    "*",
                    constants.event.node_deactivated,
                    {
                        address = address,
                        name = name
                    }
                );
            end

            --- If node is marked as connected but alive timout is reached, wait 'constants.ttl.node' longer before fully disconnecting
            if connected and (ttl + constants.ttl.node < computer.uptime()) then
                node:reboot("Timed out");

                logger:info("Node '" .. name .. "' stopped responding. Disconnected.");


                packet_handling.send_packet_event(
                    "*",
                    constants.event.node_disconnected,
                    {
                        address = address,
                        name = name
                    }
                );
            end
        end
    end
end

--<< Threads end >>--




--<< Main Functions >>--

--- Initialize logger
local function init_log()

    local logger_init_success, logger_init_result = Logger.create(
        constants.name.core,
        shared_data.file_log,
        shared_data.log_print,
        shared_data.log_debug,
        shared_data.log_verbose,
        shared_data.log_buffer
    );


    if not logger_init_success or type( logger_init_result ) ~= "table" then

        error("Error whilst initializing logger: " .. tostring( logger_init_result ));

    end

    shared_data.logger = logger_init_result;
    logger = logger_init_result;

    logger:info("Logger initialized.");

end

--- Initialize terminal
local function init_terminal()

    logger:debug("To-be overriden log function" .. tostring( shared_data.logger.log ))

    shared_data.terminal = Terminal.create("cluster-core", shared_data.logger);

end


--- Main loop function, executed once every 5 seconds
local function loop()

    if shared_data.running and shared_data.publishing then

        --- Broadcast list of registered Nodes and their data
        Packet.create(
            modem.address,
            "*",
            constants.port.main_data,
            constants.packet.data,
            {
                nodes = shared_data.nodes.contents,
                nodes_data = shared_data.nodes_data
            }
        ):send();

    end

end

--- Main startup function, executed once at startup
local function startup()
    
    local time_startup = computer.uptime();


    shared_data.update_var_running(true);


    init_log();

    init_terminal();


    logger:info("----- STARTUP -----", false);
    logger:info("Starting up...\n");



    --- Load nodes from disk
    logger:info("Loading Nodes from disk...");

        local success_nodes_load, result_nodes_load = node_handling.nodes_load();

        if success_nodes_load then
            logger:info("Success.");
        else
            logger:error("Nodes could not be loaded: " .. tostring(result_nodes_load));
        end

    logger:info("Done.\n");
    --- Load nodes from disk end



    --- Configure modem
    logger:info("Configuring modem...");

        if modem.isWireless() then

            modem.setStrength(400);
                logger:info("Modem strength set to 400.\n");

        end


        modem.open(constants.port.main);
            logger:info("Modem port 'MAIN:" .. constants.port.main .. "' opened.\n");

        modem.setWakeMessage(shared_data.message_wake);
            logger:info("Modem wake-up message set to '" .. shared_data.message_wake .. "'.");

    logger:info("Done.\n");
    --- Configure modem end



    --- Retrieve local keys
    logger:info("Retrieving local keypair...");

        local success_keypair, result_keypair = shared_data.retrieve_keys();

        if success_keypair then

            --- If 'result_keypair' is present, keys were newly generated  TODO: add check and don't just assume everthing worked as expected
            if result_keypair then

                logger:warn("Keypair could not be retrieved. Regenerated.");

            end

        else

            error("Error whilst retrieving local keypair: " .. tostring( result_keypair ));
            ---@diagnostic disable-next-line: undefined-field
            os.shutdown();

        end

    logger:info("Done.\n");
    --- Retrieve local keys end



    --- Register event handlers
    logger:info("Registering event handlers...");

        event.listen("packet_incoming", packet_handling.handle_packet);
            logger:info("Listener 'packet_incoming' registered.");

    logger:info("Done.\n");
    --- Register event handlers end



    --- Start loop
    logger:info("Starting loop...");

        timer_loop = event.timer(5, loop, math.huge);

    logger:info("Done.\n");
    --- Start loop end



    --- Start threads
    logger:info("Starting threads...");

        thread_interrupt_handler = thread.create(interrupt_handler);
            logger:info("Thread 'interrupt_handler' started.");

        thread_packet_processor = thread.create(packet_processor);
            logger:info("Thread 'packet_processor' started.");

        thread_alive_processor = thread.create(alive_processor);
            logger:info("Thread 'alive_processor' started.");

    logger:info("Done.\n");
    --- Start threads end



    local time_startup_finished = computer.uptime() - time_startup;
    logger:info("Successfully started up in " .. time_startup_finished .. " seconds.\n\n");


    while shared_data.running do

        local command = shared_data.terminal:read(shared_data.terminal_history, core_command_handling.tab_completer);

        shared_data.terminal:redraw_input_line(true);

        core_command_handling.command_handler(command);

    end

end

--- Main shutdown function, executed once at shutdown
local function shutdown()

    local time_shutdown = computer.uptime();


    logger:info("----- SHUTDOWN -----", false);
    logger:info("Shutting down...\n");



    --- Disconnect nodes
    logger:info("Disconnecting Nodes...");

        for _, node in pairs( shared_data.nodes.contents ) do
            node:disconnect{
                reason = "Core Shutdown"
            };
        end

    logger:info("Done.\n");
    --- Disconnect nodes end



    --- Save nodes to disk
    logger:info("Saving Nodes to disk...");

        local success_save, result_save = node_handling.nodes_save();

        if not success_save then
            logger:error("Nodes could not be saved to disk: " .. tostring(result_save));
        end

    logger:info("Done.\n");
    --- Save nodes to disk end




    --- Configure modem
    logger:info("Configuring modem...");

        modem.close(constants.port.main);
            logger:info("Modem port 'MAIN:" .. constants.port.main .. "' closed.");

    logger:info("Done.\n");
    --- Configure modem end



    --- Unregister event handlers
    logger:info("Unregistering event handlers...");

        event.ignore("packet_incoming", packet_handling.handle_packet);
            logger:info("Listener 'packet_incoming' unregistered.");

    logger:info("Done.\n");
    --- Unregister event handlers end



    --- Stop loop
    logger:info("Stopping loop...");

        event.cancel(timer_loop);

    logger:info("Done.\n");
    --- Stop loop end



    local time_shutdown_finished = computer.uptime() - time_shutdown;
    logger:info("Successfully shut down in " .. time_shutdown_finished .. " seconds.");




    shared_data.terminal:close(shared_data.logger);

    logger:close();
    logger:transfer();


    os.exit(0);

end

--<< Main functions end >>--




startup();

-- TODO: waitForAny or waitForAll?
local success, result = thread.waitForAny{
    thread_interrupt_handler,
    thread_packet_processor,
    thread_alive_processor
};

print("exec proc cluster-core.lua: " .. tostring(success) .. " | " .. tostring(result));

shutdown();
