local component = require("component");
local serial = require("serialization");

local data = component.data;
local modem = component.modem;
--

--


--- Server (remote) public key
local key_public_server_file = io.open("/etc/keys/server_public.key", "rb");
local key_public_server =
    data.deserializeKey(
        key_public_server_file:read("*a"),
        "ec-public"
    )
;
key_public_server_file:close();
---


local key_public, key_private = data.generateKeyPair(384); --- Client (local) keypair
local key_crypt = data.md5( data.ecdh(key_private, key_public_server) ); --- ECDH key from client's private and server's public key


--- Packet along with client's public key and init vector (iv) in header and data in body
local _packet = {
    header = {
        key_public = key_public.serialize(),
        iv = data.random(16)
    },

    data = serial.serialize("Hello World!")
};

--- Encrypt cleartext data using init vector (iv) and ECDH key (key_crypt)
_packet.data = data.encrypt(_packet.data, key_crypt, _packet.header.iv);


modem.broadcast(1, serial.serialize(_packet));
modem.open(1);