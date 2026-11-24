--[[
    Cluster-Core - Packet Handling
    In- and outgoing packet handling for Cluster-Core
    Functions for communicating in the cluster network
--]]


-- Libraries and components
local shared_data = require("cluster/core/core-shared_data");
local node_handling = require("cluster/core/core-node_handling");

local codec = require("cluster/codec");
local constants = require("cluster/constants");
local dns = require("cluster/dns-library");
local Packet = require("cluster/network_packet");
local utils_crypt = require("cluster/utils-crypt");

local computer = require("computer");
local event = require("event");


local data = shared_data.data;
--

-- Data tables
local packet_handling = {}; --- Library table

local packet_handler = {};  --- Packet handlers
--




--<< Incoming Packet Handling >>--

--- Pushes given packet to packet queue
function packet_handling.handle_packet(_, _packet)

    table.insert(shared_data.packet_queue, _packet);
    shared_data.logger:verbose("Incoming packet '" .. tostring( "_packet" ) .. "' added to queue.");

end

--- Calls suitable packet handler for given packet. Called by packet_processor thread
--- @param _packet string Encoded network packet
--- @return boolean success, string? error
function packet_handler.generic(_packet)

    local success, error = xpcall(
        function()

            shared_data.logger:debug("_packet: " .. tostring(_packet));

            local packet = Packet:decode( _packet );

            if not packet then
                error("Failed to decode packet");
            end

            if packet_handler[ packet.type ] then

                shared_data.logger:verbose("Handling packet '" .. packet.id .. ":" .. packet.type .. "'");

                packet_handler[ packet.type ]( packet );

            else

                shared_data.logger:warn("No suitable packet handler for incoming packet '" .. packet.id .. "' found. Firing type-specific computer-event.");

                event.push("packet_" .. packet.type:lower(), packet:encode());

            end

        end,

        function(error)

            shared_data.logger:error("Incoming packet '" .. "packet.id" .. ":" .. tostring( "_packet" ) .. "' raised an error: " .. tostring( error ));

        end
    );

    return success, error;

end

function packet_handler.HANDSHAKE(packet)

    shared_data.logger:verbose("Processing HANDSHAKE packet.");

    local address = packet.sender;
    local name = packet.data.name or "N/A";
    local key_public = packet.data.key_public;

    local do_connect = not node_handling.node_connected(address);
    local registered = node_handling.node_registered(address);

    local message = (
        do_connect
        and "Handshake succeeded"
        or "Already connected"
    );


    if key_public and not registered then
        key_public = data.deserializeKey(key_public, "ec-public");

        local suc, res = utils_crypt.store(key_public, name);
        local suc, res = utils_crypt.store(key_public, address);

        if suc then
            shared_data.logger:info("Stored public key for node '" .. name .. "' ('" .. address .. "').");
        else
            shared_data.logger:error("Failed to store public key for node '" ..
                name .. "' ('" .. address .. "'): " .. tostring(res));
            -- TODO: assess whether this qualifies as a critical failure or not
        end

        -- TODO: avoid having to store the public key under both name and address
    end

    shared_data.logger:verbose("Sending HANDSHAKE response.");

    --- Respond with success of handshake and registration state
    packet_handling.send_packet(
        constants.packet.handshake,
        address, -- TODO: when older-version nodes send handshake packet without public key, manually uploading the key to the core under the node's name is insufficient
        -- since the network-daemon looks for a key named after the 'address' we pass here. but passing the node's name relies on a connected and working Node-DNS for name resolution
        constants.port.main,
        {
            success = do_connect,
            message = message,
            registered = registered
        }
    );


    if do_connect then
        shared_data.logger:info("Node '" .. name .. "' handshaked.");
    else
        return shared_data.logger:warn("Handshake with '" .. name .. "' failed. Already connected to that address.");
    end



    --- If node is already registered then connection is fully established, so set data in node object
    if registered then
        local node = node_handling.node_get(address);


        local name_current = node.name;

        if name_current ~= name then
            dns.entry_edit(name_current, address, name);
        end


        node.name = name;
        node.connected = true;
        node.status = true;
        node.ttl = computer.uptime() + constants.ttl.node;
        shared_data.nodes_data[address] = {};


        shared_data.logger:info("Node '" ..
            name ..
            "' connected." .. ((name_current ~= name) and " Previously named '" .. tostring(name_current) .. "'" or ""));


        --- Broadcast event
        packet_handling.send_packet_event(
            "*",
            constants.event.node_connected,
            {
                address = address,
                name = name
            }
        );
    else
        --- If Node is not registered yet, but allowed to connect, set pending state accordingly
        node_handling.nodes_pending[address] = do_connect;
    end
end

function packet_handler.REGISTER(packet)
    local address = packet.sender;
    local name = packet.data.name or "N/A";
    local pending = node_handling.node_pending(address);
    local do_register = not node_handling.node_registered(address);
    local message = (
        pending
        and do_register
        and "Registration succeeded"
        or "Already registered"
        or "Not connected"
    );



    --- Respond with success of registration
    packet_handling.send_packet(
        constants.packet.register,
        address,
        constants.port.main,
        {
            success = pending and do_register,
            message = message
        }
    );


    if pending and do_register then
        local node = node_handling.node_register(address, name);

        node_handling.nodes_pending[address] = nil; -- Remove from pending list to prevent memory leak

        -- Set the node as connected and active, similar to the handshake for a registered node.
        node.connected = true;
        node.status = true;
        node.ttl = computer.uptime() + constants.ttl.node;
        shared_data.nodes_data[address] = {};

        shared_data.logger:info("Node '" .. name .. "' registered.");

        --- Broadcast event
        packet_handling.send_packet_event(
            "*",
            constants.event.node_registered,
            {
                address = address,
                name = name
            }
        );


        shared_data.logger:info("Node '" .. name .. "' connected.");

        --- Broadcast event
        packet_handling.send_packet_event(
            "*",
            constants.event.node_connected,
            {
                address = address,
                name = name
            }
        );
    else
        return shared_data.logger:warn("Registering of '" .. name .. "' failed: " .. message);
    end
end

function packet_handler.ALIVE(packet)
    local address = packet.sender;
    local connected = node_handling.node_connected(address);
    local node = node_handling.node_get(address);


    --- If node is connected, send alive packet and refresh node object data, else try to reboot node (see node.reboot function)
    if connected then
        --- If node returned from temporary inactivity, notify cluster
        if not node.status then
            packet_handling.send_packet_event(
                "*",
                constants.event.node_activated,
                {
                    address = address,
                    name = node.name
                }
            );
        end

        node:alive();

        shared_data.logger:verbose("Node '" .. node.name .. "' sent alive packet.");
    else
        if node then
            node:reboot("Not connected");

            shared_data.logger:warn("Disconnected Node '" .. node.name .. "' sent alive packet. Trying to reboot node.");
        else
            shared_data.logger:warn("Unknown Node '" .. address .. "' sent alive packet. Check configuration.");
        end
    end
end

function packet_handler.DATA(packet)
    local address = packet.sender;
    local connected = node_handling.node_connected(address);
    local node = node_handling.node_get(address);


    --- If node is connected, refresh internal data and activity TTL of node
    if connected then
        if node then
            if not node.status then
                packet_handling.send_packet_event(
                    "*",
                    constants.event.node_activated,
                    {
                        address = address,
                        name = node.name
                    }
                );
            end

            node:active();
        end

        shared_data.nodes_data[address] = packet.data;

        shared_data.logger:verbose("Node '" .. (node and node.name or address) .. "' sent data packet.");
    end
end

function packet_handler.RESPONSE(packet)
    --- Simply push event with packet id for identification, along with full packet
    -- event.push("packet_response", packet.data.id, packet:encode());
end

function packet_handler.DISCONNECT(packet)
    local address = packet.sender;

    --- If node is connected, disconnect
    if node_handling.node_connected(address) then
        node_handling.node_shutdown(address, "Closed connection");
    end
end

--<< Incoming Packet Handling end >>--



--<< Outgoing Packet Handling >>--

--- Constructs and sends network packet of given type to given receiver at given port with given data payload
--- @param type PacketType
--- @param receiver string
--- @param port Port
--- @param data table|any
--- @param options table?
---
--- @return boolean success, string? error
function packet_handling.send_packet(type, receiver, port, data, options)
    return Packet.create(

        shared_data.modem.address,
        receiver,
        port,
        type,
        data

    ):send(options);
end

--- Constructs and fires given event as network broadcast
--- @return boolean success, string? error
function packet_handling.send_packet_event(receiver, _event, _event_payload)
    return Packet.create(

        shared_data.modem.address,
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



--<< Internal Data Handling >>--

--- Handle data from node implementation to this common node      * node impl -> common node *   (-> core)
function packet_handling.handle_internal_data(_, data)
    shared_data.internal_data = codec.decode(data);
end

--- Send data from node implementation to core for further processing     (node impl ->)   * common node -> core *
function packet_handling.publish_internal_data(data)
    return packet_handling.send_packet_data(data or shared_data.internal_data);
end

--<< Internal Data Handling end >>--




--- Return library table
packet_handling.packet_handler = packet_handler;
return packet_handling;
