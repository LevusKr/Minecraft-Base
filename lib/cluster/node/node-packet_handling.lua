--[[
    Cluster-Node - Packet Handling
    In- and outgoing packet handling for Cluster-Node
    Functions for communicating in the cluster network
--]]


-- Libraries and components
local shared_data = require("cluster/node/node-shared_data");

local codec = require("cluster/codec");
local constants = require("cluster/constants");
local Packet = require("cluster/network_packet");

local computer = require("computer");
local event = require("event");
--

-- Data tables
local packet_handling = {}; --- Library table

local packet_handler = {};  --- Packet handlers
--




--<< Incoming Packet Handling >>--

--- Handles 'network_receive' event and adds packet to queue
-- function packet_handling.handle_network(_, message)

--     local packet = Packet:decode( message );

--     if packet and packet.id and packet.type then

--         if packet_handler[ packet.type ] then

--             event.push("packet_incoming", packet:encode());
--             shared_data.logger:verbose("Handling packet '" .. packet.id .. ":" .. packet.type .. "'");

--         else

--             shared_data.logger:warn("No suitable packet handler for incoming packet '" .. packet.id .. "' found. Firing type-specific computer-event.");
--             event.push("packet_" .. packet.type:lower(), packet:encode());

--         end

--     else

--         -- TODO: this allows spam packets to spam the terminal
--         shared_data.logger:error("Incoming packet could not be decoded: " .. tostring( packet ));

--     end

-- end


--- Calls suitable packet handler for given packet. Called on 'packet_incoming' event
function packet_handler.generic(_, _packet)

    local success, error = xpcall(
        function()

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

            shared_data.logger:error("Incoming packet '" .. "packet.id" .. ":" .. tostring( _packet ) .. "' raised an error: " .. tostring( error ));

        end
    );

end

-- TODO: redirect unmodifying packet handlers here to avoid boilerplate (currently all packets except RESPONSE lolz)
function packet_handler.CLUSTER_DEFAULT(packet)

    event.push("cluster_" .. packet.type:lower(), packet:encode());

end

--- Do not handle handshake packet here, instead hand to available listeners (e.g. main initial handshake callback in perform_handshake)
function packet_handler.HANDSHAKE(packet)

    event.push("cluster_handshake", packet:encode());

    shared_data.ttl_alive = computer.uptime() + constants.ttl.node + 2;

end

--- Do not handle register packet here, instead hand to available listeners (e.g. main initial register callback in perform_register)
function packet_handler.REGISTER(packet)

    event.push("cluster_register", packet:encode());

    shared_data.ttl_alive = computer.uptime() + constants.ttl.node + 2;

end

-- TODO: timeout when no "ack-alive" packet is received? i.e. alive packet subsequently received after sending an alive packet
function packet_handler.ALIVE(packet)

    event.push("cluster_alive", packet:encode());

    shared_data.ttl_alive = computer.uptime() + constants.ttl.node + 2;

end

--- Hand packet down to Node-Implementation via 'cluster_data' event
function packet_handler.DATA(packet)

    event.push("cluster_data", packet:encode());

end

--- Simply push event with packet id for identification, along with full packet
function packet_handler.RESPONSE(packet)

    -- event.push("packet_response", packet.data.id, packet:encode());

end

--- Fires internal event with cluster network event packet (events are usually fired by core, e.g. when a node (dis-)connects etc.)
--- Since all Node's data is being broadcast periodically, this is not meant for synchronising data (although it isn't an error to do so),
--- but rather for precise data update listeners, without having to observe possible table updates in broadcast data.
function packet_handler.EVENT(packet)

    event.push("cluster_event", packet:encode());

end

--- Handle disconnect initiated by core
-- TODO: handle disconnect properly
function packet_handler.DISCONNECT(packet)

    shared_data.logger:debug("Handling disconnect packet '" .. packet.id .. "'");

    shared_data.update_var_handshaked( false );
    shared_data.update_var_registered( false );
    shared_data.update_var_connected( false );
    shared_data.update_var_publishing( false );

    shared_data.logger:debug("Disconnect variables updated.");

    local reason_disconnect = packet.data.reason;
    local do_shutdown = packet.data.shutdown;
    local do_reboot = packet.data.reboot;

    shared_data.logger:debug("Disconnect reason: " .. tostring( reason_disconnect ) .. ", shutdown: " .. tostring( do_shutdown ) .. ", reboot: " .. tostring( do_reboot ));

    event.push("cluster_disconnect", packet:encode());

    shared_data.logger:debug("Cluster disconnect event fired.");

    if do_reboot then

        shared_data.logger:debug("Rebooting computer.");
        computer.shutdown( true );

    elseif do_shutdown then

        shared_data.logger:debug("Shutting down computer.");
        computer.shutdown();

    end

end

--<< Incoming Packet Handling end >>--



--<< Outgoing Packet Handling >>--

--- Constructs and sends network packet of given type to given receiver at given port with given data payload
function packet_handling.send_packet(type, receiver, port, data, options)

    return Packet.create(

        shared_data.modem.address,
        receiver,
        port,
        type,
        data

    ):send( options );

end

--- Constructs and sends network packet of given type to Core server with given data payload
function packet_handling.send_packet_internal(type, data, options)

    return packet_handling.send_packet(
        type,
        constants.name.core,
        constants.port.main,
        data or {
            name = shared_data.hostname
        },
        options or {
            encrypt = shared_data.encrypt_network
        }
    );

end

function packet_handling.send_packet_handshake(data)

    return packet_handling.send_packet_internal(
        constants.packet.handshake,
        {
            name = shared_data.hostname,
            key_public = shared_data.key_public.serialize() -- TODO: add nil check and make sending conditional. currently, the node stores no information about the last registration state, but rather expects to may not be registered every new connect. this means we have to send the public key every time.
        }
    );

end

function packet_handling.send_packet_register(data)

    return packet_handling.send_packet_internal(
        constants.packet.register,
        data
    );

end

function packet_handling.send_packet_alive(data)

    return packet_handling.send_packet_internal(
        constants.packet.alive,
        data
    );

end

function packet_handling.send_packet_data(data)

    return packet_handling.send_packet_internal(
        constants.packet.data,
        data,
        {
            encrypt = shared_data.encrypt_network
        }
    );

end

function packet_handling.send_packet_disconnect(data)

    return packet_handling.send_packet_internal(
        constants.packet.disconnect,
        data
    );

end

--<< Outgoing Packet Handling end >>--



--<< Internal Data Handling >>--

--- Handle data from node implementation to this common node      * node impl -> common node *   (-> core)
function packet_handling.handle_internal_data(_, data)

    shared_data.internal_data = codec.decode( data );

end

--- Send data from node implementation to core for further processing     (node impl ->)   * common node -> core *
function packet_handling.publish_internal_data(data)

    return packet_handling.send_packet_data(data or shared_data.internal_data);

end

--<< Internal Data Handling end >>--




--- Return library table
packet_handling.packet_handler = packet_handler;
return packet_handling;