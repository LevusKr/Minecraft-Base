--[[
    Network-Daemon
    This daemon provides advanced functionality to communicate with other machines in the network and
    handles split packet reassembly and packet decryption.
    Also this intercepts send|broadcast calls to modem components, replacing dns resolvable hostnames with functional modem addresses.
--]]


-- Files and Configurations
--

-- Libraries and components
local codec = require("cluster/codec");
local constants = require("cluster/constants");
local dns = require("cluster/dns-library");
local Future = require("cluster/future");
local network = require("cluster/network");
local Packet = require("cluster/network_packet");

local utils = require("cluster/utils");
local utils_crypt = require("cluster/utils-crypt");

local component = require("component");
local computer = require("computer");
local event = require("event");

local modem = component.modem;
local data = component.isAvailable("data") and component.data or nil;
--

-- Variables and constants
local hostname = utils.internal.hostname();

local address_local = component.modem.address;
local address_dns = network.address_dns();
local address_core = network.address_core();



local component_invoke = component.invoke; --- Original method, for later restoring
--

-- Data tables
local packet_assembly = {}; --- Store packet fragments while waiting for more fragments
--





--<< Daemon Functions >>--

--- Handles raw 'modem_message' events and if receiving packets, reassembles, decompresses and decrypts packets
function handle_message(_, sender, _, _, _, message, is_compressed, is_encrypted, index, total, seq)

    --- If 'total' count is greater than just (this) one packet, expect more split packets to follow
    if total and total > 1 then

        --- If no table is allocated for given sequence (first split packet), prepare empty table
        if not packet_assembly[ seq ] then

            packet_assembly[ seq ] = {};

        end


        --- Insert split packet into memory already at correct index
        packet_assembly[ seq ][ index ] = message;


        --- If all packets from current sequence arrived, assemble. Otherwise return here until all parts arrive
        if #packet_assembly[ seq ] == total then

            message = table.concat(packet_assembly[ seq ], "");
            packet_assembly[ seq ] = nil;

        else
            return
        end

    end


    --- If packet is compressed, decompress it
    if is_compressed then

        assert(data, "No data card available");


        message = data.inflate( message );

    end


    --- If packet is encrypted, decrypt it using iv and public key from header and local private key
    if is_encrypted then

        assert(data, "No data card available");


        message = codec.decode( message );


        local key_public = data.deserializeKey(
            message.header.key_public,
            "ec-public"
        );


        local key_crypt_success, key_crypt = utils_crypt.key_crypt( key_public ); --- Retrieve or generate ECDH crypt key from remote public and local private key

        --- If ECDH crypt key is present, decrypt, otherwise pass unmodified (encrypted) packet with header
        if not key_crypt_success then

            event.onError("Unable to calculate crypt key. Incoming message could not be decrypted.");
            return

        end


        message.data = data.decrypt(message.data, key_crypt, message.header.iv);

        message = message.data; --- Remove encryption header since it's no longer needed

    end



    local packet = Packet:decode( message );

    --- Push signal according to format of network message
    -- TODO: properly determine full valid packet
    if packet and type(packet) == "table" and packet.id and packet.type then

        if packet.type == constants.packet.response then

            event.push("packet_response_"..(packet.data and packet.data.id), packet:encode());

        else

            event.push("packet_incoming", packet:encode());

        end

        packet = nil;

    else

        -- event.onError("Incoming packet could not be decoded: " .. tostring( packet ));
        event.push("network_receive", message);

    end


end

--- Override 'component.modem.send|broadcast' method call
function override_network()

    component.invoke = function(address, method, ...)

        local component_type = component.type( address );

        --- If invoked method is not modem.send or modem.broadcast, do nothing
        if component_type == "modem" and (method == "send" or method == "broadcast") then

            local args = {...};
            local receiver = method == "send" and args[1] or "*";
            local skip_lookup = false;

            local success = false;
            local response = nil;



            --- If receiver already is an address instead a resolveable hostname OR '*' for broadcasting, skip lookup
            if network.validate_address( receiver ) or receiver == "*" then

                skip_lookup = true;

            end


            --- If receiver is pointing at own modem, send internal modem_message, skip lookup
            if receiver == hostname or receiver == address or receiver == "localhost" or receiver == "127.0.0.1" then

                event.push(
                    "modem_message",
                    address,
                    address,
                    args[2],
                    0,
                    select(3, table.unpack( args ))
                );


                skip_lookup = true;

            end


            --- If no valid response is found yet, search local hosts for match
            if not skip_lookup then

                if receiver == constants.name.dns then

                    if not address_dns then

                        event.onError("Configure DNS address in '/etc/network.cfg'.");

                    end

                    response = address_dns;
                    skip_lookup = true;

                elseif receiver == constants.name.core then

                    if not address_core then

                        event.onError("Configure Core address in '/etc/network.cfg'.");

                    end

                    response = address_core;
                    skip_lookup = true;

                end

            end


            --- If lookup doing should indeed be done, do it
            if not skip_lookup then

                --- Finally retrieve valid address from dns cache, which optionally queries dns server (see dns-library)
                success, response = dns.lookup( receiver );

                if not success then

                    event.onError("Unable to resolve hostname '" .. tostring( receiver ) .. "': " .. tostring( response ));

                end

            end


            --- If response is anything but nil, replace hostname with an valid address in modem.send's arguments
            args[1] =
                response ~= nil
                and response
                or args[1]
            ;


            --- Invoke component method with modified args and return result
            return component_invoke(address, method, table.unpack( args ));

        else

            return component_invoke(address, method, ...);

        end

    end



    --- Automatically create dns entry for local address, normally this is done along registration at core so just redundancy checking here
    --- Defaults to local hostname and modem address
    dns.create(_, _, true):on_failure(
        function(result)

            if result ~= "Hostname already exists" then

                event.onError("Failed to create own dns entry: " .. tostring( result ));

            end

        end
    );

end

--<< Daemon Functions end >>--




--<< RC Handling >>--

--- RC API start function - Listen to network messages
function start()

    event.listen("modem_message", handle_message);

    override_network();


    computer.usedMemory = function()

        return computer.totalMemory() - computer.freeMemory();

    end

end

--- RC API stop function - XXX
function stop()

    event.ignore("modem_message", handle_message);

    component.invoke = component_invoke;

end

--<< RC Handling >>--