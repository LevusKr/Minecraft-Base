--[[
    Network-Library
    This library provides functionality to communicate with the local network deamon (network-daemon.lua)
    by sending internal signals via event.push(...).
--]]


-- Files and Configurations

--

-- Libraries and components
local os = require("os");
local utils = require("cluster/utils");
local component = require("component");
local event = require("event");
local thread = require("thread");
local dns = require("dns");

local modem = component.modem;
--

-- Variables and Constants

--

-- Data tables
local network = {};
-- 




function network.send_packet(receiver, port, data) -- tell daemon to send data by pushing an event
  event.push("network_send", receiver, port, data); -- TODO: data size and type etc.
end


local function tick()
  --
end



return network;