--[[
    Cluster-Core - Event Handling
    TODO: description
]]


-- Libraries and components
local shared_data = require("cluster/core/core-shared_data");
local packet_handling = require("cluster/core/core-packet_handling");

local codec = require("cluster/codec");
local constants = require("cluster/constants");
local dns = require("cluster/dns-library");
local Node = require("cluster/network_node");
local Packet = require("cluster/network_packet");

local computer = require("computer");
local event = require("event");
--

-- Data tables
local event_handling = {}; --- Library table
--




--<< Event Handling >>--

--- Publishes the given event with the given data to the cluster
--- @param event EventType
--- @param data any
---
--- @return boolean success, string? error
function event_handling.publish(event, data)
    return packet_handling.send_packet_event(
        "*",
        event,
        data
    );
end

function event_handling.handshake()
    -- 
end

function event_handling.register()
    -- 
end

--- Publishes node connected event
--- @param address string
--- @param name string
---
--- @return boolean success, string? error
function event_handling.node_connected(address, name)
    return event_handling.publish(constants.event.node_connected, {
        address = address,
        name = name
    });
end

function event_handling.deregister()
    -- 
end

function event_handling.data()
    -- 
end

function event_handling.alive()
    -- 
end

--- Publishes node disconnected event
--- @param address string
--- @param name string
--- @param reason string
---
--- @return boolean success, string? error
function event_handling.node_disconnected(address, name, reason)
    return event_handling.publish(constants.event.node_disconnected, {
        address = address,
        name = name,
        reason = reason
    });
end

--<< Event Handling end >>--




--- Return library table
return event_handling;
