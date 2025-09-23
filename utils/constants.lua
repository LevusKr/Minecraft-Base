--[[
    Constants
    Collection of constants sorted by category.
    Including global names, durations and numbers, etc.
--]]


-- Libraries and components
--

-- Data tables
--- @enum constants
--- @module 'cluster/constants'
local constants = {
    name = { --- Node names
        core   = "core",
        dns    = "node-dns",
        update = "node-update",
        log    = "node-log",
        tablet = "node-tablet",
        nas    = "node-nas"
    },
    port = { --- Modem ports
        main      = 1, -- SNMP: 161
        main_data = 2,
        event     = 3,
        remote    = 23,
        dns       = 53,

        space_station = 69, -- nice   TODO: change

        logistics = 100,
        energy    = 101,
        oxygen    = 102,
        fluid     = 103,
        items     = 104,

        file     = 115,
        log      = 514,
        update   = 8530,
        
        elevator = 1000
    },
    packet = { --- Network packet types
        handshake  = "HANDSHAKE",
        register   = "REGISTER",
        alive      = "ALIVE",
        data       = "DATA",
        response   = "RESPONSE",
        event      = "EVENT",
        disconnect = "DISCONNECT"
    },
    ttl = { --- Various Time-to-live durations
        dns    = 300, --- 5 x 60 seconds
        packet = 10,
        node   = 10
    },
    env = { --- Environmental variables
        hostname      = "CLUSTER_HOSTNAME",
        running       = "CLUSTER_RUNNING",
        handshaked    = "CLUSTER_HANDSHAKED",
        registered    = "CLUSTER_REGISTERED",
        connected  	  = "CLUSTER_CONNECTED",
        publishing    = "CLUSTER_PUBLISHING",
        internal_data = "CLUSTER_INTERNAL_DATA"
    },
    buffer = { --- Various buffer sizes
        log    = 1600, --- 64 Bytes average log length x 25 Logs
        packet = 20
    },
    event = { --- Event names
        node_connected    = "NODE_CONNECTED",
        node_registered   = "NODE_REGISTERED",
        node_activated    = "NODE_ACTIVATED",
        node_deactivated  = "NODE_DEACTIVATED",
        node_disconnected = "NODE_DISCONNECTED",
        node_alarmed      = "NODE_ALARMED"
    },
    sound = { --- Sound names
        success = "SUCCESS",
        failure = "FAILURE",
        info    = "INFO",
        warning = "WARNING",
        severe  = "SEVERE",
        error   = "ERRROR"
    }
};
    -- constants.name = {}; --- Node names
    -- constants.port = {}; --- Modem ports
    -- constants.packet = {}; --- Network packet types
    -- constants.ttl = {}; --- Various Time-to-live
    -- constants.env = {}; --- Environmental variables
    -- constants.buffer = {}; --- Various buffer sizes
    -- constants.event = {}; --- Event names
    -- constants.sound = {}; --- Sound names
--




-- Constants
-- constants.name.core = "core";
-- constants.name.dns = "node-dns";
-- constants.name.update = "node-update";
-- constants.name.log = "node-log";
-- constants.name.tablet = "node-tablet";
-- constants.name.nas = "node-nas";

-- constants.port.main = 1; -- SNMP: 161
-- constants.port.main_data = 2;
-- constants.port.event = 3;
-- constants.port.remote = 23;
-- constants.port.dns = 53;
-- constants.port.space_station = 69; -- nice   TODO: change
-- constants.port.logistics = 100;
-- constants.port.energy = 101;
-- constants.port.oxygen = 102;
-- constants.port.fluid = 103;
-- constants.port.items = 104;
-- constants.port.file = 115;
-- constants.port.log = 514;
-- constants.port.update = 8530;
-- constants.port.elevator = 1000;

-- constants.packet.handshake = "HANDSHAKE";
-- constants.packet.register = "REGISTER";
-- constants.packet.alive = "ALIVE";
-- constants.packet.data = "DATA";
-- constants.packet.response = "RESPONSE";
-- constants.packet.event = "EVENT";
-- constants.packet.disconnect = "DISCONNECT";

-- constants.ttl.dns = 300; --- 5 x 60 seconds
-- constants.ttl.packet = 10;
-- constants.ttl.node = 10;

-- constants.env.hostname = "CLUSTER_HOSTNAME";
-- constants.env.running = "CLUSTER_RUNNING";
-- constants.env.handshaked = "CLUSTER_HANDSHAKED";
-- constants.env.registered = "CLUSTER_REGISTERED";
-- constants.env.connected = "CLUSTER_CONNECTED";
-- constants.env.publishing = "CLUSTER_PUBLISHING";
-- constants.env.internal_data = "CLUSTER_INTERNAL_DATA";

-- constants.buffer.log = 1600; --- 64 Bytes average log length x 25 Logs
-- constants.buffer.packet = 20;

-- constants.event.node_connected = "NODE_CONNECTED";
-- constants.event.node_registered = "NODE_REGISTERED";
-- constants.event.node_activated = "NODE_ACTIVATED";
-- constants.event.node_deactivated = "NODE_DEACTIVATED";
-- constants.event.node_disconnected = "NODE_DISCONNECTED";
-- constants.event.node_alarmed = "NODE_ALARMED";

-- constants.sound.success = "SUCCESS";
-- constants.sound.failure = "FAILURE";
-- constants.sound.info = "INFO";
-- constants.sound.warning = "WARNING";
-- constants.sound.severe = "SEVERE";
-- constants.sound.error = "ERRROR";
--




--- Return API Data as table
return constants;