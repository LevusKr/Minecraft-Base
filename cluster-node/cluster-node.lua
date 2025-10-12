--[[
    Cluster-Node
    Custom component of network cluster structure
    A Node acts as part of the network, thus being connected to the core
    and publishing information about a connected machine, e.g. nuclear reactor
--]]


-- Libraries and components
local shared_data = require("cluster/node/shared_data");
local packet_handling = require("cluster/node/packet_handling");

local constants = require("cluster/constants");
local _event = require("cluster/event");
local Logger = require("cluster/logger");
local Packet = require("cluster/network_packet");

local computer = require("computer");
local event = require("event");
local os = require("os");
local term = require("term");


local modem = shared_data.modem;
--

-- Variables and constants
local logger = shared_data.logger;

local timer_loop = 0;
--

-- Data tables
local packet_handler = packet_handling.packet_handler; --- Packet handlers for packet types (e.g. packet_handler.HANDSHAKE for handshake packets)
--




--<< Main Functions >>--

--- Globally available (e.g. via RC api) function for connecting to core
function connect()

    if not shared_data.connected then

        return perform_handshake();

    end

    return false, "Already connected";

end

--- Underlying function for connecting to core
-- TODO: eventually timeout and fail, then exit or reboot etc.
function perform_handshake()

    packet_handling.send_packet_handshake();
    logger:info("Sent handshake packet.");


    local success, result = _event.await("cluster_handshake");

    if success then

        local response = Packet:decode( result );


        --- Whether Core server accepts handshake request
        shared_data.update_var_handshaked( response.data.success );

        if shared_data.handshaked then
            
            logger:info("Handshake succeeded.");

        else

            logger:error("Handshake with core failed: " .. tostring( response.data.message ));
            return;

        end


        --- Whether Node is already registered at Core server
        shared_data.update_var_registered( response.data.registered );

        if shared_data.registered then

            logger:info("Connection established.");

            shared_data.update_var_connected( true );
            
            event.push("cluster_connect");

        end

    else

        -- TODO: if handshaking was not successful, shutdown cluster-node daemon?

        logger:error("Handshake with core failed: " .. tostring(result or "Timed out"));

    end


    if shared_data.handshaked and not shared_data.registered then

        perform_register();

    end



    return shared_data.handshaked, shared_data.registered;

end



--- Globally available (e.g. via RC api) function for registering at core
function register()

    if not shared_data.registered then

        return perform_register();

    end

    return false, "Already registered";

end

--- Underlying function for registering at core
-- TODO: eventually timeout and fail, then exit or reboot etc.
function perform_register()

    packet_handling.send_packet_register();

    logger:info("Sent register packet.");


    local success, result = _event.await("cluster_register");

    if success then

        local response = Packet:decode( result );


        --- Whether Core server accepts register request
        shared_data.update_var_registered( response.data.success );


        if shared_data.registered then

            logger:info("Connection established.");

            shared_data.update_var_connected( true );

            event.push("cluster_connect");

        else

            logger:error("Registering at core denied: " .. tostring( response.data.message ));

        end

    else

        -- TODO: if registering was not successful, shutdown cluster-node daemon?

        logger:error("Registering at core failed: " .. tostring(result or "Timed out"));

    end



    return shared_data.registered;

end



--- Globally available (e.g. via RC api) function for disconnecting from core
function disconnect()

    if shared_data.connected then

        return perform_disconnect();

    end

    return false, "Not connected";

end

--- Underlying function for disconnecting from core
function perform_disconnect()

    packet_handling.send_packet_disconnect();
    
    logger:info("Sent disconnect packet.");
    
    shared_data.update_var_handshaked( false );
    shared_data.update_var_registered( false );
    shared_data.update_var_connected( false );
    shared_data.update_var_publishing( false );


    return true;

end



--- Update volatile booleans in shared_data and respective environmental variables ---
function update_var(variable, state)

    if shared_data["update_var_" .. variable] then
        
        return shared_data["update_var_" .. variable]( state );

    end

end



--- Initialize logger
local function init_log()

    shared_data.file_log = string.format(shared_data.file_log, shared_data.hostname);

    local logger_init_success, logger_init_result = Logger.create(
        shared_data.hostname,
        shared_data.file_log,
        shared_data.log_print,
        shared_data.log_debug,
        shared_data.log_verbose,
        shared_data.log_buffer
    );


    if not logger_init_success then

        error("Error whilst initializing logger: " .. tostring( logger_init_result ));

    end


    shared_data.logger = logger_init_result;
    logger = logger_init_result;

end

--- Main loop function, executed once every second
local function loop()

    if shared_data.connected then

        packet_handling.send_packet_alive();

        if shared_data.ttl_alive < computer.uptime() then

            -- no alive received from core
            -- TODO: somehow when bearing with high, most likely blocking load (disk i/o), alive packets from core are missed and the node disconnects itself
            --stop();

        end


        if shared_data.publishing then

            packet_handling.publish_internal_data();

        end

    end

end

--- Main startup function, executed once at startup
function start()

    local time_startup = computer.uptime();

    shared_data.update_var_running( true );

    init_log();



    term.clear();
    logger:info("----- STARTUP -----", false);
    logger:info("Starting up...\n");



    --- Configure modem
    logger:info("Configuring modem...");

        if modem.isWireless() then

            modem.setStrength(400);
                logger:info("Modem strength set to 400.\n");

        end

        modem.open( constants.port.main );
            logger:info("Modem port 'MAIN:" .. constants.port.main .. "' opened.\n");

        modem.setWakeMessage( shared_data.message_wake );
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

            logger:error( tostring( result_keypair) );

        end

    logger:info("Done.\n");
    ---



    --- Register event handlers
    logger:info("Registering event handlers...");

        -- event.listen("network_receive", packet_handling.handle_network);
        --     logger:info("Listener 'network_receive' registered.");

        event.listen("packet_incoming", packet_handler.generic);
            logger:info("Listener 'packet_incoming' registered.");

        event.listen("internal_data", packet_handling.handle_internal_data);
            logger:info("Listener 'internal_data' registered.");

    logger:info("Done.\n");
    --- Register event handlers end



    --- Start loop
    logger:info("Starting loop...");

        timer_loop = event.timer(shared_data.loop_interval, loop, math.huge);

    logger:info("Done.\n");
    --- Start loop end



    --- Start threads
    logger:info("Starting threads...");

    logger:info("Done.\n ");
    --- Start threads end




    local time_startup_finished = computer.uptime() - time_startup;
    logger:info("Successfully started up in " .. time_startup_finished .. " seconds.\n\n");



    perform_handshake();
    
end

--- Main shutdown function, executed once at shutdown
function stop()

    local time_shutdown = computer.uptime();


    logger:info("----- SHUTDOWN -----", false);
    logger:info("Shutting down...\n");



    --- Configure modem
    logger:info("Configuring modem...");

        modem.close( constants.port.main );
            logger:info("Modem port 'MAIN:" .. constants.port.main .. "' closed.");

    logger:info("Done.\n");
    --- Configure modem end



    --- Unregister event handlers
    logger:info("Unregistering event handlers...");

        -- event.ignore("network_receive", packet_handling.handle_network);
        --     logger:info("Listener 'network_receive' unregistered.");

        event.ignore("packet_incoming", packet_handler.generic);
            logger:info("Listener 'packet_incoming' unregistered.");

        event.ignore("internal_data", packet_handling.handle_internal_data);
            logger:info("Listener 'internal_data' unregistered.");

    logger:info("Done.\n");
    --- Unregister event handlers end



    --- Stop loop
    logger:info("Stopping loop...");

        event.cancel( timer_loop );

    logger:info("Done.\n");
    --- Stop loop end




    local time_shutdown_finished = computer.uptime() - time_shutdown;
    logger:info("Successfully shut down in " .. time_shutdown_finished .. " seconds.");




    if shared_data.connected then

        disconnect();

    end


    --- Closes and rotates logger, returns success of rotation (if current log file exceeded limit) and file to-be transfered (if succeeded, returned file is compressed file)
    local success_rotate, result_rotate = logger:rotate();

    --- If rotating suceeded, returned file 'result_rotate' is compressed file to-be transfered
    if success_rotate then

        logger:info("Logger file has been rotated. Transfering...")


        local success_transfer, result_transfer = logger:transfer( { path = result_rotate } );

        if success_transfer then

            logger:info("Transfer succeeded.");

        else

            logger:error("Transfer failed: " .. tostring( result_transfer ));

        end

    else

        logger:error("Logger file could not be rotated: " .. tostring( result_rotate ));

    end


    shared_data.update_var_running( false );

    os.exit(0);

end

--<< Main Functions end >>--
