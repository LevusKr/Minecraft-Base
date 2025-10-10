--- @module 'cluster/network'
--[[
    Network-Library
    This library provides functionality for networking,
    such as computer's network configuration and sending/receiving packets.
--]]


-- Libraries and components
local codec = require("cluster/codec");
local Config = require("cluster/config");
local event = require("cluster/event");
local Future = require("cluster/future");
local utils_crypt = require("cluster/utils-crypt");

local component = require("component");
local _event = require("event");
local os = require("os");
--local Packet = require("cluster/network_packet");

local modem = component.modem;
local data = component.isAvailable("data") and component.data or nil;
--

-- Files and Configurations
local config_network_path = "/etc/network.cfg";
local config_network = Config:create( config_network_path );
--

-- Data tables
local network = {};
--




--<< API Methods >>--

--- Load network configuration (/etc/network.cfg)
--- @return Config
function network.config()

    return config_network:load();

end

--- Retrieve configured dns server address from network config
function network.address_dns()

    return config_network:get("address_dns", {reload = true});

end

--- Retrieve configured core server address from network config
function network.address_core()

    return config_network:get("address_core", {reload = true});

end

--- Retrieve configured server address from network config
function network.address(name)

    return config_network:get(name, {reload = false});

end


--- General function to encode network payload as string
function network.encode(payload)

    payload =
        (payload or {}).encode -- This checks if the given payload (if it's a table/object/class etc.) contains an own encode function...
            and payload:encode() -- ...and calls it...
            or codec.encode( payload ) -- ...or falls back to the codec library.
    ;


    return true, payload;

end

--- General function to encrypt network payload with given ECDH crypt key
function network.encrypt(payload, key_crypt, options)

    assert(data, "No data card available");


    options = options or {};


    --- If 'key_crypt' is not a valid key but a key's name, try to retrieve locally stored ECDH crypt key
    -- We sadly have to rely on the caller to tell us whether the passed 'key_crypt' is an actual key or a stored key's name,
    -- since both are strings and thus not easily distinguishable, performance- and security-wise
    if options.is_name then

        local success_key_crypt, result_key_crypt = utils_crypt.key_crypt( key_crypt ); --- 'key_crypt' is a name

        if not success_key_crypt then

            return false, result_key_crypt;

        end

        key_crypt = result_key_crypt;

    end


    --- If 'payload' is not a string, try to encode as string
    if type( payload ) ~= "string" then

        local success_encode, payload_encode = network.encode( payload );

        if not success_encode then

            return false, "Encoding of network payload failed";

        end


        payload = payload_encode;

    end


    --- Retrieve machine's local public key
    local success_key_public, key_public = utils_crypt.key_public();

    if not success_key_public then

        return false, "Unable to retrieve local public key";

    end


    local payload_data = payload; --- Actual payload data i.e. without overhead for encryption

    payload = {
        header = {
            iv = utils_crypt.generate_iv();
            key_public = key_public.serialize();
        },

        data = nil
    };

    payload.data = data.encrypt(payload_data, key_crypt, payload.header.iv);



    return true, payload;

end

--- General function to compress and, if needed, split network payload into several smaller data fractions (if payload > max_fraction_size)
---
--- @return boolean success Whether the operation succeeded
--- @return table result Table containing payload, a unique sequence id and how the payload has been modified
--- result = {
---     seq = ...,
---     is_compressed = ...,
---     is_splitted = ...,
---     result = ...
--- }
function network.compress(payload, is_encoded, is_encrypted)

    local max_fraction_size = (8192 - 40); --- Note: -40 because of other packet parameters (is_compressed: bool, index: num, total: num, seq: string) and overhead for these four values + overhead for data (5 * overhead) (bool: 4 B, num: 8 B, seq: 10 B, general value overhead: 2 B   ->   4+8+8+10 + 5*2 = 40 Bytes)
    
    local is_compressed = false; --- Whether packet data has been compressed
    local is_splitted = false; --- Whether packet data has been split

    local seq = network.generate_packet_id(); --- Sequence number to identify fractions of the same packet (10-digits, 10 Bytes)

    local success = false; --- Whether operation succeeded and packet/s has/have been send.
    local result = {}; --- Return value. Can be table of packets or error message


    --- If payload is not string-encoded yet OR it is encrypted and thus only partly string-encoded (see network.encrypt, encryption overhead is not string-encoded yet), string-encode here
    if (not is_encoded) or (is_encrypted) then

        local success_encode, payload_encode = network.encode( payload );

        if not success_encode then

            return false, "Encoding of network payload failed";

        end


        payload = payload_encode;

        is_encoded = true;

    end


    -- If payload exceeds limitation, try to compress and/or alternatively split into multiple smaller packets
    if #payload > max_fraction_size then

        --- If Data card is available, try to compress packet
        if data then

            local compression_result, message_error = component.data.deflate( payload );

            --- If compression succeeded, simply override payload variable for further processing and mark 'is_compressed' as true
            if compression_result then

                payload = compression_result;

                is_compressed = true;

            else

                _event.onError("Deflate compression of network packet failed: " .. message_error);

            end

        end


        --- If (possibly compressed) payload still exceeds limitation, split into smaller packets.
        if #payload > max_fraction_size then

            local index = 0; --- Index of current payload fraction
            local total = math.ceil(#payload / max_fraction_size); --- Count of total payload fractions

            repeat

                --- Split payload every 'max_fraction_size' Bytes.
                --- Fraction#1 -> Byte#1 to Byte#max_fraction_size
                --- Fraction#2 -> Byte#(max_fraction_size + 1) to Byte#(max_fraction_size * 2)
                --- Fraction#3 -> Byte#(max_fraction_size * 2 + 1) to Byte#(max_fraction_size * 3)
                --- ...

                --- End of previous fraction frame (so next frame starts at this value + 1)
                --- 0 * max_fraction_size
                --- 1 * max_fraction_size
                --- 2 * max_fraction_size
                --- ...
                local prev_frame_end = index * max_fraction_size;

                --- 0 * max_fraction_size + 1  ->  0 * max_fraction_size + max_fraction_size
                --- 1 * max_fraction_size + 1  ->  1 * max_fraction_size + max_fraction_size
                --- 2 * max_fraction_size + 1  ->  2 * max_fraction_size + max_fraction_size
                --- ...
                payload = payload:sub(prev_frame_end + 1, prev_frame_end + max_fraction_size);


                index = index + 1;


                result[ index ] = payload;


            until index == total

            is_splitted = true;
            success = true;

        else

            --- Compressing of payload did the job, succeed
            success = true;
            
            result = payload;

        end

    else

        --- Still succeed if compression wasn't needed so we can call this function preventive every time (result is here already 'result_encode' or if pre-encoded, set to payload)
        success = true;

        result = payload;

    end


    result = {
        seq = seq,
        is_compressed = is_compressed,
        is_splitted = is_splitted,
        result = result
    }

    return success, result;

end

--- General function to simply send (encoded) data over the network - may be used for implementing a custom protocol
--- @param receiver string Remote modem address or DNS hostname
--- @param port number Remote modem port
--- @param data any Payload data
--- @param options table Options TODO: defaults
---
--- @return boolean success
--- @return string|nil result Possible error message
function network.send(receiver, port, data, options)

    if receiver == nil then
        return false, "No receiver specified";
    elseif port == nil then
        return false, "No port specified";
    elseif data == nil then
        return false, "No data to send";
    end

    local options_default = {
        open_port = true,
        encode = true,
        encrypt = false,
        key_crypt = receiver
    };
    options_default.__index = options_default;
    options = setmetatable(options or {}, options_default);



    local success, payload = false, data; --- Default 'payload' to raw data
    local is_encoded = false; --- Whether packet data is string-encoded
    local is_encrypted = false; --- Whether packet data is encrypted
    local is_compressed = false; --- Whether packet data is compressed


    --- If enabled, string-encode data either by calling it's own (data.encode), or generic (codec.encode) encode function
    if options.encode then

        local success_encode, payload_encode = network.encode( data );

        if not success_encode then

            return false, "Encoding of network payload failed";

        end


        payload = payload_encode;

        is_encoded = true;

    end



    --- If enabled, encrypt data with given ECDH crypt key or locally stored one
    if options.encrypt then

        if not options.key_crypt then

            return false, "No encryption key or key name provided";

        end


        local success_encrypt, payload_encrypt = false, "Broadcast not allowed for encryption";

        if receiver ~= "*" then

            success_encrypt, payload_encrypt = network.encrypt(payload, options.key_crypt, {is_name = (options.key_crypt == receiver) and true or false});

        end

        if not success_encrypt then

            return false, "Encryption failed: " .. tostring( payload_encrypt );

        end

        payload = payload_encrypt;

        is_encrypted = true;

    end



    local success_compress, result_compress = network.compress(payload, is_encoded, is_encrypted);

    if success_compress then

        payload = result_compress.result;
        is_compressed = result_compress.is_compressed;

    else

        return false, "Error while compressing network payload: " .. tostring( result_compress.result );

    end

    --- If compressing (and eventually splitting) payload succeed, send each fraction OR send packet as-is
    if result_compress.is_splitted then

        local seq = result_compress.seq; --- Sequence number to identify fractions as one packet
        local total = #payload;


        for index, payload_fraction in pairs( payload ) do

            if receiver == "*" then

                modem.broadcast(
                    port,
                    payload_fraction,
                    is_compressed,
                    is_encrypted,
                    index,
                    total,
                    seq
                );

            else

                modem.send(
                    receiver,
                    port,
                    payload_fraction,
                    is_compressed,
                    is_encrypted,
                    index,
                    total,
                    seq
                );

            end

        end

    else

        --- If receiver is '*', broadcast, otherwise send directly to receiver
        if receiver == "*" then

            success = modem.broadcast(port, payload, is_compressed, is_encrypted);

        else

            success = modem.send(receiver, port, payload, is_compressed, is_encrypted);

        end

    end

    --- If enabled, automatically open local port for receiving response data belonging to this packet
    if options.open_port then

        modem.open( port );

    end


    --- Finally, return if sending (and optionally encoding|encrypting) the message succeeded   TODO: maybe allow soft-encode? if encoding is enabled and fails, still send raw data instead of returning false immediatly
    return success;

end

--- Implementation of above send function for internal cluster packet protocol
--- @param packet Packet Network packet
--- @param options table Options TODO: defaults
---
--- @return boolean success
--- @return string? result Optional error message
function network.send_packet(packet, options)

    local success, result = network.send(

        packet.receiver,
        packet.port,
        packet,
        options or {}

    );

    return success, result;

end

--- Waits infinitely or 'timeout' duration for 'packet_response_${packet_id}' event to occur
--- @param packet Packet
--- @param timeout? number Timeout duration in seconds
--- 
--- @return boolean success
--- @return Packet? packet_response
function network.await(packet, timeout)

    local success, _packet_response = event.await("packet_response_"..packet.id, timeout);

    return success, success and packet:decode( _packet_response ) or _packet_response;

end

--- Listens in background infinitely or timeout duration for 'packet_response' event to occur and if the packet id matches, calls callback function with response packet (non-blocking)
--- @async
--- 
--- @param packet Packet
--- @param callback function
--- @param timeout? number Timeout duration in seconds
--- 
--- @return number id_listener OpenOS event id for referencing and/or cancelling
function network.await_async(packet, callback, timeout)

    local helper = function(_, _, _packet_response)

        local packet_response = packet:decode( _packet_response );

        callback( packet_response );

    end


    return event.await_async(
        "packet_response",
        helper,
        event.filter_first("packet_response", packet.id),
        timeout
    );

end

--- Wraps response packet awaition as future, either sync or asynchronous
function network.await_future(packet, async, timeout)

    return Future:create(

        network.await,
        packet,
        timeout

    ):run( async );

end


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


local characters_alphanumeric = "abcdefghijklmnopqrstuvwxyzABZDEFGHIJKLMNOPQRSTUVWXYZ0123456789"; -- TODO: move
--- Generates a n-digit, unique, alphanumeric id
function network.generate_packet_id()

    math.randomseed( math.floor( os.time() ) );

    local id = "";

    for i = 1, 10 do

        local index = math.random(62);
        id = id..characters_alphanumeric:sub(index, index);

    end

    -- 48-57 -> "0-9"
    -- 65-90 -> "A-Z"
    -- 97-122 -> "a-z"

    return id;

end


local pattern = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"; -- TODO: move
--- Validates that given string is a uuid
function network.validate_address(address)

    checkArg(1, address, "string");

    return address:match( pattern );

end

--<< API Methods end >>--




--- Return API Methods as table
return network;