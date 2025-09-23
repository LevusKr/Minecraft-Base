--[[
    Network-Node
    This class provides functionality for creating network nodes,
    which represent physical nodes in the network cluster.
--]]


-- Libraries and components
local codec = require("cluster/codec");
local constants = require("cluster/constants");
local network = require("cluster/network");
local Packet = require("cluster/network_packet");

local computer = require("computer");
local component = require("component");
local event = require("event");

local modem = component.modem;
--

-- Data tables
--- @class Node
--- @module 'cluster/network_node'
local Node = {
    name = "unknown",
    address = "unknown",
    connected = false,
    status = false,
    ttl = -1
};
Node.__index = Node;
--




--<< Class Methods >>--

--- Instantiate new node with given address and name
--- @param address string
--- @param name string
---
--- @return Node
function Node:create(address, name)
    local node = {};

    if type(address) == "string" then --- If called with single parameters

        node = setmetatable({
            name = name,
            address = address,
            connected = true,
            status = true,
            ttl = computer.uptime() + 5
        }, Node);

    elseif type(address) == "table" then --- If called with a ready-to-go table (e.g. after decoding)

        node = setmetatable(address, Node);

    end


    return node;
end


--- Sends a network packet from primary modem component to specified node address
--- @param type constants Packet type
--- @param data any Payload data
--- 
--- @return boolean success
--- @return string packet_id Packet id for later referencing RESPONSE packet
--- @return string result
function Node:send(type, data, options)

    return Packet:create(

        modem.address,
        self.address,
        constants.port.main,
        type,
        data

    ):send( options );

end

--- Marks node as active and thus refreshes status and ttl
function Node:active()

    self.connected = true;
    self.status = true;
    self.ttl = computer.uptime() + constants.ttl.node;

end

function Node:inactive()

    self.status = false;
    self.ttl = -1;

end

--- Refreshes status and informs node of active connection by sending (usually as respond to previously received alive packet) alive packet
--- @param options table Options TODO: defaults
--- 
--- @return boolean success, string packet_id, string result
function Node:alive(options)

    options = options or {};

    options.encrypt = options.encrypt ~= nil and options.encrypt or true;



    if not options.packet_only then

        self:active();

    end

    return self:send(
        constants.packet.alive,
        _,
        options
    );

end

--- Disconnects node by sending disconnect packet
--- @param options table Options TODO: defaults
--- 
--- @return boolean success, string packet_id, string result
function Node:disconnect(options)

    options = options or {};

    options.encrypt = options.encrypt ~= nil and options.encrypt or true;


    self.connected = false;
    self.status = false;
    self.ttl = -1;

    return self:send(
        constants.packet.disconnect,
        {
            reason = options.reason or "Connection closed",
            shutdown = options.shutdown,
            reboot = options.reboot
        },
        {
            encrypt = options.encrypt
        }
    );

end

--- Sends a wakeup message from primary modem component to specified node address
function Node:wakeup()

    return modem.send(self.address, constants.port.remote, self.address .. self.name);

end

--- Tries to shutdown node by disconnecting it
function Node:shutdown(reason_disconnect)

    return self:disconnect(
        {
            reason = reason_disconnect,
            shutdown = true
        }
    );

end

--- Tries to reboot node by disconnecting and then waking it up again
function Node:reboot(reason_reboot)

    return self:disconnect(
        {
            reason = reason_reboot,
            reboot = true
        }
    );

    --self:wakeup();

end


--- Encode node to string for storing or networking
function Node:encode()

    return codec.encode( self );

end

--- Decode string to table and instantiate node
function Node.decode(raw)

    return Node:create( codec.decode( raw ) );

end

--<< Class Methods end >>--




--- Return class object
return Node;