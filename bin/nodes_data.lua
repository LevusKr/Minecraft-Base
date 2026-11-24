local event = require('event');
local serial = require('serialization');
local constants = require('cluster/constants');
local Packet = require('cluster/network_packet');


local _, _packet = event.pull(5, 'cluster_data');

local packet = Packet:decode( _packet );
if (packet.port ~= constants.port.main_data) then return; end


--- Handle nodes and nodes' data broadcast from core here

local nodes = packet.data.nodes or {};
local nodes_data = packet.data.nodes_data or {};

--print(serial.serialize(nodes, true));
print(serial.serialize(nodes_data, true));
