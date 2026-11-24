--[[
    Stats Library
    Provides standardized statistics tracking for classical server nodes (DNS, NAS, Log, Update)
--]]

local computer = require("computer");

local Stats = {};
Stats.__index = Stats;

function Stats.create(server_name)
    local self = setmetatable({}, Stats);
    self.server_name = server_name;
    self.uptime_start = computer.uptime();
    
    self.requests_total = 0;
    self.responses_total = 0;
    self.responses_success = 0;
    self.responses_failure = 0;
    self.bytes_in = 0;
    self.bytes_out = 0;
    
    --- Counters for operations (e.g. { ["query"] = 154, ["exists"] = 42 })
    self.operations = {};
    
    --- Counters for clients by sender address/name (e.g. { ["reactor-node"] = 89, ["tablet"] = 12 })
    self.clients = {};
    
    --- Counters for operation details (e.g. { ["hostnames"] = {...}, ["files"] = {...} })
    self.details = {};

    --- Counters for errors (e.g. { ["hostnames"] = {...}, ["files"] = {...} })
    self.errors = {};
    
    return self;
end

--- Record incoming request
function Stats:record_request(client, operation, bytes)
    self.requests_total = self.requests_total + 1;
    self.bytes_in = self.bytes_in + (bytes or 0);
    
    if client then
        self.clients[client] = (self.clients[client] or 0) + 1;
    end
    if operation then
        self.operations[operation] = (self.operations[operation] or 0) + 1;
    end
end

--- Record outgoing response
function Stats:record_response(success, bytes)
    self.responses_total = self.responses_total + 1;
    self.bytes_out = self.bytes_out + (bytes or 0);
    if success then
        self.responses_success = self.responses_success + 1;
    else
        self.responses_failure = self.responses_failure + 1;
    end
end

--- Record domain-specific detail metrics (e.g. DNS hostname or NAS file path)
function Stats:record_detail(category, key)
    if not category or not key then return end
    self.details[category] = self.details[category] or {};
    self.details[category][key] = (self.details[category][key] or 0) + 1;
end

--- Record error
function Stats:record_error(client, operation, err)
    if not client or not operation or not err then return end
    self.errors[client] = self.errors[client] or {};
    self.errors[client][operation] = self.errors[client][operation] or {};
    self.errors[client][operation][err] = (self.errors[client][operation][err] or 0) + 1;
end

--- Export clean snapshot of current stats
function Stats:export()
    return {
        server_name = self.server_name,
        uptime = computer.uptime() - self.uptime_start,
        requests_total = self.requests_total,
        responses_total = self.responses_total,
        responses_success = self.responses_success,
        responses_failure = self.responses_failure,
        bytes_in = self.bytes_in,
        bytes_out = self.bytes_out,
        operations = self.operations,
        clients = self.clients,
        details = self.details,
        errors = self.errors
    };
end

return Stats;