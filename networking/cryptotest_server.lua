local component = require("component");
local event = require("event");
local serial = require("serialization");

local data = component.data;
--

--


--- Server's private key
local key_private_file = io.open("/etc/keys/private.key", "rb");
local key_private =
    data.deserializeKey(
        key_private_file:read("*a"),
        "ec-private"
    )
;
key_private_file:close();
---


local _, _, _, _, _, packet = event.pull("modem_message");
packet = serial.unserialize( packet );


local key_public_client = data.deserializeKey(packet.header.key_public, "ec-public"); --- Client's public key
local key_crypt = data.md5( data.ecdh(key_private, key_public_client) ); --- ECDH key from servers's private and client's public key

--- Decryot data using init vector (iv) and ECDH key (key_crypt)
local data = serial.unserialize( data.decrypt(packet.header.data, key_crypt, packet.header.iv) );


print(data);
