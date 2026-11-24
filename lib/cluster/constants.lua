--[[
    Constants
    Collection of constants sorted by category.
    Including global names, durations and numbers, etc.
--]]

-- Libraries and components
--

---@enum NodeName
local NodeName = {
    core   = "core",
    dns    = "node-dns",
    update = "node-update",
    log    = "node-log",
    tablet = "node-tablet",
    nas    = "node-nas"
}

---@enum Port
local Port = {
    main          = 1, -- SNMP: 161
    main_data     = 2,
    event         = 3,
    remote        = 23,
    dns           = 53,
    space_station = 69, -- nice   TODO: change
    logistics     = 100,
    energy        = 101,
    oxygen        = 102,
    fluid         = 103,
    items         = 104,
    file          = 115,
    log           = 514,
    update        = 8530,
    elevator      = 1000
}

---@enum PacketType
local PacketType = {
    handshake  = "HANDSHAKE",
    register   = "REGISTER",
    alive      = "ALIVE",
    data       = "DATA",
    response   = "RESPONSE",
    event      = "EVENT",
    disconnect = "DISCONNECT"
}

---@enum TTL
local TTL = {
    dns    = 300, --- 5 x 60 seconds
    packet = 10,
    node   = 25
}

---@enum EnvVar
local EnvVar = {
    hostname      = "CLUSTER_HOSTNAME",
    running       = "CLUSTER_RUNNING",
    handshaked    = "CLUSTER_HANDSHAKED",
    registered    = "CLUSTER_REGISTERED",
    connected     = "CLUSTER_CONNECTED",
    publishing    = "CLUSTER_PUBLISHING",
    internal_data = "CLUSTER_INTERNAL_DATA"
}

---@enum BufferSize
local BufferSize = {
    log    = 1600, --- 64 Bytes average log length x 25 Logs
    packet = 20
}

---@enum EventType
local EventType = {
    node_connected    = "NODE_CONNECTED",
    node_registered   = "NODE_REGISTERED",
    node_activated    = "NODE_ACTIVATED",
    node_deactivated  = "NODE_DEACTIVATED",
    node_disconnected = "NODE_DISCONNECTED",
    node_alarmed      = "NODE_ALARMED"
}

---@enum LogLevel
local LogLevel = {
    info    = "INFO",
    warn    = "WARN",
    error   = "ERROR",
    debug   = "DEBUG",
    verbose = "VERBOSE"
}

---@enum SoundName
local SoundName = {
    success = "SUCCESS",
    failure = "FAILURE",
    info    = "INFO",
    warning = "WARNING",
    severe  = "SEVERE",
    error   = "ERRROR"
}


-- Data tables
local constants = {
    name         = NodeName,
    port         = Port,
    packet       = PacketType,
    ttl          = TTL,
    env          = EnvVar,
    buffer       = BufferSize,
    event        = EventType,
    log          = LogLevel,
    sound        = SoundName,

    alphanumeric = "abcdefghijklmnopqrstuvwxyzABZDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
    uuid_pattern = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"
};

--- Return API Data as table
return constants;
