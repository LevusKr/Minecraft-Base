--- @module 'cluster/network_packet'
--[[
    Network-Packet
    This class provides functionality for creating network packets,
    along with integrated functionality to en-/decode and send packets await related response packets.
--]]


-- Libraries and components
local codec = require("cluster/codec");
local constants = require("cluster/constants");
local network = require("cluster/network");

local modem = require("component").modem;
--


-- Data tables
--[[
    Packet Structure:
        packet = {
            id = 7f8h34                                 --random 6-digit id
            sender = abcd-abcd-abcd-abcd or hostname    --actual sender, may be a hostname
            receiver = abcd-abcd-abcd-abcd or hostname  --actual receiver, may be a hostname
            port = 0-65535                              --actual port
            payload = string or number or table or ...  --actual payload
        }
--]]
--- @class Packet
---
--- @field id string
--- @field sender string
--- @field receiver string
--- @field port number
--- @field type string
local Packet = {
    sender = "unknown",
    receiver = constants.name.core,
    port = constants.port.main,
    type = constants.packet.data,
    data = {}
};
Packet.__index = Packet;
--




--<< Class Methods >>--

--- Instantiate new packet with given parameters. First argument 'sender' could also be a table containing packet information (see Packet:decode).
--- @param sender string Local modem address or DNS hostname
--- @param receiver string Remote modem address or DNS hostname
--- @param port Port Remote modem port
--- @param _type PacketType Packet type
--- @param data any Payload data
--- 
--- @return Packet?
--- 
--- @overload fun(_: _, packet: table):Packet
function Packet.create(sender, receiver, port, _type, data)

    local packet = nil;

    if type(sender) == "string" then --- If called with single parameters

        packet = setmetatable({

            id = network.generate_packet_id(),
            sender = sender,
            receiver = receiver,
            port = port,
            type = _type,
            data = data
    
        }, Packet);

    elseif type(sender) == "table" then --- If called with a ready-to-go table. (e.g. after decoding)

        packet = setmetatable(sender, Packet);

    end


    return packet;

end

--- Send string encoded packet via network. Optionally encrypt with given ECDH crypt key or default key
--- @return boolean success, string? error
function Packet:send(options)

    return network.send_packet(self, options);

end

--- Encode packet to string for storing or networking
--- @return string
function Packet:encode()

    return codec.encode( self );

end

--- Decode string to table and instantiate packet
--- @param raw string
--- 
--- @return Packet?
function Packet:decode(raw)

    if raw then
        return Packet.create( codec.decode( raw ) );
    end

end

--- Retrieve size of packet as encoded string. Also returns said string
--- @return number size, string packet_encoded
function Packet:size()

    local packet_encoded = self:encode();

    return #packet_encoded, packet_encoded;

end

--- Await response to this (previously sent) packet, either blocking or asynchronously wrapped by a Future object   TODO: check if packet has been sent, or you're gonna wait forever
function Packet:await_response(async, timeout)

    -- if async then

        return network.await_future(self, async, timeout);

    -- else

        -- return network.await(self, timeout);

    -- end

end

--- Wrapper for Packet#await_response. If a RESPONSE packet has been received, this pulls the response packet's data table up.
--- This replaces and deletes the actual full packet as the future's result, call Packet#await_response if you need the full packet.
--- The following handlers that mostly only care about the packet's data won't see the unimportant packet this way.
function Packet:await_response_direct(async, timeout)

    local response_future = self:await_response(async, timeout);

    response_future:on_success(
        function(packet_response)

            response_future.result = packet_response.data;

        end
    );


    return response_future;

end

--- Create response to this (previously received) packet. This function takes care of including the received packet's id for referencing
--- @param response table|any Response payload
function Packet:create_response(response)

    response = response or {};

    if type( response ) ~= "table" then
        response = {response};
    end

    response.id = self.id;


    return Packet.create(
        modem.address,
        self.sender,
        self.port,
        constants.packet.response,
        response
    );

end

--- Send response to this (previously received) packet. This function takes care of including the received packet's id for referencing
--- @param response table|any Response payload
function Packet:send_response(response, options)

    return self:create_response(response):send( options );

end

--<< Class Methods end >>--




--- Return class object
return Packet;
