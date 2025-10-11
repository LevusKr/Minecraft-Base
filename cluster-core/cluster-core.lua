--[[
    Cluster-Core
    Main component of network cluster structure
    The Core acts as central head of the network, thus having active connections
    to every registered Node and monitoring their activity.
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/core-%s.log";
local file_log_num = "/var/log/cluster/core-num";

local file_nodes = "/etc/nodes.cfg";
--

-- Libraries and Components
local codec = require("cluster/codec");
local Config = require("cluster/config");
local constants = require("cluster/constants");
local dns = require("cluster/dns-library");
local _event = require("cluster/event");
local Logger = require("cluster/logger");
local network = require("cluster/network");
local Node = require("cluster/network_node");
local Packet = require("cluster/network_packet");
local Terminal = require("cluster/terminal");
local utils_string = require("cluster/utils-string");
local utils_crypt = require("cluster/utils-crypt");

local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local serialization = require("serialization");
local term = require("term");
local thread = require("thread");

local modem = component.modem;
local data = component.data;
--

-- Variables and constants
local logger = nil;
local log_print = true;
local log_debug = true;
local log_verbose = false;
local log_buffer = true;

local terminal = nil;
local terminal_history = {}; --- Add often used commands here to quickly access them

local message_wake = nil;


local running = false;
local publishing = false;

local timer_loop = 0;
local thread_interrupt_handler = nil;

local thread_packet_processor = nil;
local packet_processor_interval = 0.2; --- Seconds between runs

local thread_alive_processor = nil;
local alive_processor_interval = 0.2; --- Seconds between runs
--

-- Data tables
local packet_handler = {}; --- Packet handlers for packet types (e.g. packet_handler.HANDSHAKE for handshake packets)
local packet_queue = {}; --- Packet queue for incoming packets

local nodes = Config:create( file_nodes ); --- {123abc = {name = "node-n", address = "123abc", state = false, ttl = 5}, ...}
local nodes_by_name = {};
local nodes_data = {}; --- Nodes latest data (avoid deep-nesting in nodes table for efficiency)
local nodes_pending = {}; --- Currently pending Nodes i.e. sent handshake packet, thus waiting for register packet
--





--<< Outgoing Packet Handling >>--

--- Constructs and sends network packet of given type to given receiver with given data payload
local function send_packet(type, receiver, data, encrypt)

    if encrypt == nil then
        encrypt = true;
    end
    
    return Packet:create(

        modem.address,
        receiver,
        constants.port.main,
        type,
        data

    ):send( {encrypt = encrypt} );
    
end

--- Constructs and fires given event as network broadcast
local function send_packet_event(receiver, _event, _event_payload)
    
    return Packet:create(

        modem.address,
        receiver,
        constants.port.event,
        constants.packet.event,
        {
            event = _event,
            payload = _event_payload
        }

    ):send();
    
end

--<< Outgoing Packet Handling end >>--





--<< Node Handling >>--

--- Constructs node with given address and name and registers it
local function node_register(address, name)

    local node = Node:create(address, name);

    nodes:set(address, node);
    nodes_data[ address ] = {};

    nodes:save();

    --- Handle DNS entry creation asynchronously since it doesn't affect their cluster connectivity directly
    local dns_response = dns.entry_create(name, address, true);

    dns_response:on_completion(function(result) logger:warn(codec.encode(result)) end);


    return node;

end

--- Returns node by given address
local function node_get(address)

    return nodes:get( address );

end

--- Whether the node with the given address is currently connected
local function node_pending(address)

    return nodes_pending[ address ];

end

--- Whether a registered node with given address exists
local function node_registered(address)

    return node_get( address ) and true or false;

end

--- Whether the node with the given address is currently connected
local function node_connected(address)

    local node = node_get( address );

    return node and node.connected or false, node;

end


--- Disconnects node with given address
local function node_start(address, reason)

    local connected, node = node_connected( address );

    if not node then
        return false, "Not found";
    elseif connected then
        return false, "Already connected";
    end



    local success, result = node:wakeup();

    if not success then
        return false, result;
    end


    logger:info("Node '" .. node.name .. "' waked up: " .. reason);


    -- TODO: fire event on wakeup?
    -- send_packet_event(
    --     "*",
    --     constants.event.node_disconnected,
    --     {
    --         address = address,
    --         name = node.name,
    --         reason = reason
    --     }
    -- );


    return true, result;

end

--- Disconnects node with given address
local function node_disconnect(address, reason)

    local connected, node = node_connected( address );

    if not node then
        return false, "Not found";
    elseif not connected then
        return false, "Not connected";
    end



    local success, result = node:disconnect();

    if not success then
        return false, result;
    end


    nodes_data[ address ] = {}; -- TODO: keep last node data in memory after disconnect? some stuff may use this as indicator for node's online status

    logger:info("Node '" .. node.name .. "' disconnected: " .. reason);


    send_packet_event(
        "*",
        constants.event.node_disconnected,
        {
            address = address,
            name = node.name,
            reason = reason
        }
    );


    return true, result;

end

--- Shuts down node with given address
local function node_shutdown(address, reason, reboot)

    local connected, node = node_connected( address );

    if not node then
        return false, "Not found";
    elseif not connected then
        return false, "Not connected";
    end



    local success, result;

    if reboot then
        success, result = node:reboot();
    else
        success, result = node:shutdown();
    end

    if not success then
        return false, result;
    end


    nodes_data[ address ] = {};

    logger:info("Node '" .. node.name .. "' shut down: " .. reason);


    send_packet_event(
        "*",
        constants.event.node_disconnected,
        {
            address = address,
            name = node.name,
            reason = reason
        }
    );


    return true, result;

end

--- Reboots node with given address
local function node_reboot(address, reason)

    return node_shutdown(address, reason, true);

end


--- Load all nodes from disk and instantiate objects
local function nodes_load()

    local success, result = nodes:load();

    if not success then

        return false, result;

    end


    for address, _node in pairs( result ) do

        local node = Node:create( _node );

        nodes_by_name[ node.name ] = address;

        nodes:set(address, node);

    end

    setmetatable(nodes.contents, {
        __index = function(_, name)
            logger:debug(nodes_by_name[ name ])
            return rawget(nodes.contents, nodes_by_name[ name ]);
        end
    });


    return true;

end

--- Save all nodes to disk. Node data is not persisted
local function nodes_save()
    
    for address, node in pairs( nodes.contents ) do

        node.connected = false;
        node.status = false;
        node.ttl = -1;

        nodes_data[ address ] = {};

    end

    return nodes:save();

end

--<< Node Handling end >>--




--<< Incoming Packet Handling >>--

--- Pushes given packet to packet queue
local function handle_packet(_, _packet)

    local packet = Packet:decode( _packet );

    table.insert(packet_queue, packet);
    logger:verbose("Incoming packet '" .. packet.id .. "' added to queue.");

end

--- Calls suitable packet handler for given packet. Called by packet_processor thread
function packet_handler.generic(packet)

    -- local packet = Packet:decode( _packet );

    -- packet_handler[ packet.type ]( packet );

    return xpcall(
        function()

            -- local packet = Packet:decode( _packet );

            if packet_handler[ packet.type ] then

                logger:verbose("Handling packet '" .. packet.id .. ":" .. packet.type .. "'");

                logger:verbose(packet:encode())
                return packet_handler[ packet.type ]( packet );

            else

                logger:warn("No suitable packet handler for incoming packet '" .. packet.id .. "' found. Firing type-specific computer-event.");

                event.push("packet_" .. packet.type:lower(), packet:encode());

            end

        end,

        function(error)

            -- TODO: print complete _packet?
            logger:error("Incoming packet '" .. "packet.id" .. ":" .. tostring( codec.encode( packet ) ) .. "' raised an error: " .. tostring( error ));

        end

        -- packet
    );

end

function packet_handler.HANDSHAKE(packet)

    local address = packet.sender;
    local name = packet.data.name or "N/A";
    local key_public = packet.data.key_public;

    local do_connect = not node_connected( address );
    local registered = node_registered( address );

    local message = (
        do_connect
        and "Handshake succeeded"
        or "Already connected"
    );


    if key_public then
        
        key_public = data.deserializeKey(key_public, "ec-public");

        local suc, res = utils_crypt.store(key_public, name);
        local suc, res = utils_crypt.store(key_public, address);

        -- TODO: avoid having to store the public key under both name and address

    end


    --- Respond with success of handshake and registration state
    send_packet(
        constants.packet.handshake,
        address, -- TODO: when older-version nodes send handshake packet without public key, manually uploading the key to the core under the node's name is insufficient
                    -- since the network-daemon looks for a key named after the 'address' we pass here. but passing the node's name relies on a connected and working Node-DNS for name resolution
        {
            success = do_connect,
            message = message,
            registered = registered
        }
    );


    if do_connect then

        logger:info("Node '" .. name .. "' handshaked.");

    else

        return logger:warn("Handshake with '" .. name .. "' failed. Already connected to that address.");

    end



    --- If node is already registered then connection is fully established, so set data in node object
    if registered then

        local node = node_get(address);


        local name_current = node.name;

        if name_current ~= name then

            dns.entry_edit(name_current, address, name);

        end


        node.name = name;
        node.connected = true;
        node.status = true;
        node.ttl = computer.uptime() + 6;
        nodes_data[ address ] = {};


        logger:info("Node '" .. name .. "' connected." .. ((name_current ~= name) and " Previously named '" .. tostring( name_current ) .. "'" or ""));


        --- Broadcast event
        send_packet_event(
            "*",
            constants.event.node_connected,
            {
                address = address,
                name = name
            }
        );

    else

        --- If Node is not registered yet, but allowed to connect, set pending state accordingly
        nodes_pending[ address ] = do_connect;

    end

end

function packet_handler.REGISTER(packet)

    local address = packet.sender;
    local name = packet.data.name or "N/A";
    local pending = node_pending( address );
    local do_register = not node_registered( address );
    local message = (
        pending
        and do_register
            and "Registration succeeded"
            or "Already registered"
        or "Not connected"
    );



    --- Respond with success of registration
    send_packet(
        constants.packet.register,
        address,
        {
            success = pending and do_register,
            message = message
        }
    );


    if pending and do_register then

        local node = node_register(address, name);

        nodes_pending[ address ] = nil; -- Remove from pending list to prevent memory leak

        -- Set the node as connected and active, similar to the handshake for a registered node.
        node.connected = true;
        node.status = true;
        node.ttl = computer.uptime() + 6;
        nodes_data[ address ] = {};

        logger:info("Node '" .. name .. "' registered.");

        --- Broadcast event
        send_packet_event(
            "*",
            constants.event.node_registered,
            {
                address = address,
                name = name
            }
        );

        
        logger:info("Node '" .. name .. "' connected.");

        --- Broadcast event
        send_packet_event(
            "*",
            constants.event.node_connected,
            {
                address = address,
                name = name
            }
        );

    else

        return logger:warn("Registering of '" .. name .. "' failed: " .. message);

    end

end

function packet_handler.ALIVE(packet)

    local address = packet.sender;
    local connected = node_connected( address );
    local node = node_get( address );


    --- If node is connected, send alive packet and refresh node object data, else try to reboot node (see node.reboot function)
    if connected then

        --- If node returned from temporary inactivity, notify cluster
        if not node.status then

            send_packet_event(
                "*",
                constants.event.node_activated,
                {
                    address = address,
                    name = node.name
                }
            );

        end

        node:alive();

        logger:verbose("Node '" .. node.name .. "' sent alive packet.");

    else

        if node then

            node:reboot("Not connected");

            logger:warn("Disconnected Node '" .. node.name .. "' sent alive packet. Trying to reboot node.");

        else

            logger:warn("Unknown Node '" .. address .. "' sent alive packet. Check configuration.");

        end


    end

end

function packet_handler.DATA(packet)

    local address = packet.sender;
    local connected = node_connected( address );
    local node = node_get( address );


    --- If node is connected, refresh internal data of node
    if connected then

        nodes_data[ address ] = packet.data;

        logger:verbose("Node '" .. node.name .. "' sent data packet.");

    end

end

function packet_handler.RESPONSE(packet)

    --- Simply push event with packet id for identification, along with full packet
    -- event.push("packet_response", packet.data.id, packet:encode());

end

function packet_handler.DISCONNECT(packet)

    local address = packet.sender;


    --- If node is connected, disconnect
    if node_connected( address ) then

        node_shutdown(address, "Closed connection");

    end

end

--<< Incoming Packet Handling end >>--




--<< Threads >>-

--- Handle program interruption. Every task depends on boolean 'running', so when running is false they clean up and exit
local function interrupt_handler()

    while running do

        event.pull("interrupted");
        running = false;

    end

end

--- Get current packet in queue and call corresponding packet handler   TODO: refactor because handle_packet won't ever fail
local function packet_processor()

    local packet = nil;
    local attempts = 0;
    local failed = false;

    while running do

        os.sleep( packet_processor_interval );

        --- If packet available, pull it
        if next( packet_queue ) then

            packet = packet_queue[1];

        end


        --- Just null-safety-checking again
        if packet then

            local success, result = packet_handler.generic( packet );

            if not success then

                logger:error("Error while handling packet: " .. tostring( result ));
                failed = true;

            end


            --- If either attempts ran out, packet got handled successfully, or finally failed -> remove from queue
            if attempts > 5 or success or failed then

                logger:verbose("Incoming packet '" .. packet.id .. "' removed from queue.");
                table.remove(packet_queue, 1);

            else

                attempts = attempts + 1;

            end

        end


        packet = nil;
        attempts = 0;
        failed = false;

    end

end

--- Iterate over nodes and refresh connection, status and ttl (i.e. check if node is dead)
local function alive_processor()

    while running do

        os.sleep( alive_processor_interval );

        for _, node in pairs( nodes.contents ) do

            local address = node.address;
            local name = node.name;
            local connected = node.connected;
            local status = node.status;
            local ttl = node.ttl;

            --- If node is connected but stopped sending alive packets (status is true but ttl is reached), send alive packet and set node's status to inactive
            if connected and status and (ttl < computer.uptime()) then

                node:alive( {packet_only = true} ); --- Send alive packet to possibly 'wake-up' node.

                node.status = false;
                --node:inactive();
                

                logger:info("Node '" .. name .. "' didn't respond in time. Sent alive packet.");


                -- TODO: "deactivation" is ambigious
                send_packet_event(
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


                send_packet_event(
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

--- Initialize terminal
local function init_terminal()

    logger:debug("To-be overriden log function" .. tostring( logger.log ))

    terminal = Terminal.create("cluster-core", logger);

end


--- Main loop function, executed once every second
local function loop()

    if running and publishing then

        --- Broadcast list of registered Nodes and their data
        Packet:create(
            modem.address,
            "*",
            constants.port.main_data,
            constants.packet.data,
            {
                nodes = nodes.contents,
                nodes_data = nodes_data
            }
        ):send();

    end

end

--- Main startup function, executed once at startup
local function startup()

    local time_startup = computer.uptime();


    running = true;

    message_wake = modem.address..constants.name.core;

    init_log();



    init_terminal();

    logger:info("----- STARTUP -----", false);
    logger:info("Starting up...\n");



    --- Load nodes from disk
    logger:info("Loading Nodes from disk...");

        local success_nodes_load, result_nodes_load = nodes_load();

        if success_nodes_load then

            logger:info("Success.");

        else

            logger:error("Nodes could not be loaded: " .. tostring( result_nodes_load ));

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

        modem.setWakeMessage(message_wake);
            logger:info("Modem wake-up message set to '" .. message_wake .. "'.");

    logger:info("Done.\n");
    --- Configure modem end



    --- Register event handlers
    logger:info("Registering event handlers...");

        -- event.listen("network_receive", handle_network);
        --     logger:info("Listener 'network_receive' registered.");

        event.listen("packet_incoming", handle_packet);
            logger:info("Listener 'packet_incoming' registered.");

    logger:info("Done.\n");
    --- Register event handlers end



    --- Start loop
    logger:info("Starting loop...");

        timer_loop = event.timer(1, loop, math.huge);

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

    logger:info("Done.\n ");
    --- Start threads end



    local time_startup_finished = computer.uptime() - time_startup;
    logger:info("Successfully started up in " .. time_startup_finished .. " seconds.\n\n");


    while running do

        local command = terminal:read(terminal_history, tab_completer);

        terminal:redraw_input_line(true);

        command_handler( command );

    end

end

--- Main shutdown function, executed once at shutdown
local function shutdown()

    local time_shutdown = computer.uptime();;


    logger:info("----- SHUTDOWN -----", false);
    logger:info("Shutting down...\n");



    --- Disconnect nodes
    logger:info("Disconnecting Nodes...");

        for _, node in pairs( nodes.contents ) do

            node:disconnect(
                {
                    reason = "Core Shutdown"
                }
            );
        
        end

    logger:info("Done.\n");
    --- Disconnect nodes end



    --- Save nodes to disk
    logger:info("Saving Nodes to disk...");

        local success_save, result_save = nodes_save();

        if not success_save then
            logger:severe("Nodes could not be saved to disk: " .. tostring( result_save ));
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

        -- event.ignore("network_receive", handle_network);
        --     logger:info("Listener 'network_receive' unregistered.");

        event.ignore("packet_incoming", handle_packet);
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



    terminal:close( logger );

    logger:close();
    logger:transfer();
    running = false;

    os.exit(0);

end

--<< Main functions end >>--




startup();

local success, result = thread.waitForAny{
    thread_interrupt_handler,
    thread_packet_processor,
    thread_alive_processor
};

shutdown();