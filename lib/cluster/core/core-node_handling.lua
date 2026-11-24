--[[
    Cluster-Core - Node Handling
    TODO: description
--]]


-- Libraries and components
local shared_data = require("cluster/core/core-shared_data");

local codec = require("cluster/codec");
local dns = require("cluster/dns-library");
local Node = require("cluster/network_node");
--

-- Data tables
local node_handling = {}; --- Library table
--




--<< Node Handling >>--

--- Constructs node with given address and name and registers it
function node_handling.node_register(address, name)
    local node = Node:create(address, name);

    shared_data.nodes:set(address, node);
    shared_data.nodes_data[address] = {};

    shared_data.nodes:save();

    --- Handle DNS entry creation asynchronously since it doesn't affect their cluster connectivity directly
    local dns_response = dns.entry_create(name, address, true);

    dns_response:on_completion(function(result) shared_data.logger:warn(codec.encode(result)) end);


    return node;
end

--- Returns node by given address
function node_handling.node_get(address)
    return shared_data.nodes:get(address);
end

--- Whether the node with the given address is currently connected
function node_handling.node_pending(address)
    return shared_data.nodes_pending[address];
end

--- Whether a registered node with given address exists
function node_handling.node_registered(address)
    return node_handling.node_get(address) and true or false;
end

--- Whether the node with the given address is currently connected
function node_handling.node_connected(address)
    local node = node_handling.node_get(address);

    return node and node.connected or false, node;
end


--- Disconnects node with given address
function node_handling.node_start(address, reason)
    local connected, node = node_handling.node_connected(address);

    if not node then
        return false, "Not found";
    elseif connected then
        return false, "Already connected";
    end



    local success, result = node:wakeup();

    if not success then
        return false, result;
    end


    shared_data.logger:info("Node '" .. node.name .. "' waked up: " .. reason);


    -- TODO: fire event on wakeup?
    -- send_packet_event(
    --     "*",
    --     constants.event.node_disconnected,
    --     {
    --         address = address,
    --         name = node.name,
    --         reason = reason
    --     }
    -- );


    return true, result;
end

--- Disconnects node with given address
function node_handling.node_disconnect(address, reason)
    local connected, node = node_handling.node_connected(address);

    if not node then
        return false, "Not found";
    elseif not connected then
        return false, "Not connected";
    end



    local success, result = node:disconnect();

    if not success then
        return false, result;
    end


    shared_data.nodes_data[address] = {}; -- TODO: keep last node data in memory after disconnect? some stuff may use this as indicator for node's online status

    shared_data.logger:info("Node '" .. node.name .. "' disconnected: " .. reason);


    local event_handling = require("cluster/core/core-event_handling");
    event_handling.node_disconnected(address, node.name, reason);



    return true, result;
end

--- Shuts down node with given address
function node_handling.node_shutdown(address, reason, reboot)
    local connected, node = node_handling.node_connected(address);

    if not node then
        return false, "Not found";
    elseif not connected then
        return false, "Not connected";
    end



    local success, result;

    if reboot then
        success, result = node:reboot();
    else
        success, result = node:shutdown();
    end

    if not success then
        return false, result;
    end


    shared_data.nodes_data[address] = {};

    shared_data.logger:info("Node '" .. node.name .. "' shut down: " .. reason);

    local event_handling = require("cluster/core/core-event_handling");
    event_handling.node_disconnected(address, node.name, reason);


    return true, result;
end

--- Reboots node with given address
function node_handling.node_reboot(address, reason)
    return node_handling.node_shutdown(address, reason, true);
end


--- Load all nodes from disk and instantiate objects
function node_handling.nodes_load()
    local success, result = shared_data.nodes:load();

    if not success or type(result) ~= "table" then
        return false, result;
    end


    for address, _node in pairs(result) do
        local node = Node:create(_node);

        shared_data.nodes_by_name[node.name] = address;

        shared_data.nodes:set(address, node);
    end

    setmetatable(shared_data.nodes.contents, {
        __index = function(_, name)
            shared_data.logger:debug(shared_data.nodes_by_name[name])
            return rawget(shared_data.nodes.contents, shared_data.nodes_by_name[name]);
        end
    });


    return true;
end

--- Save all nodes to disk. Node data is not persisted
function node_handling.nodes_save()
    for address, node in pairs(shared_data.nodes.contents) do
        node.connected = false;
        node.status = false;
        node.ttl = -1;

        shared_data.nodes_data[address] = {};
    end

    return shared_data.nodes:save();
end

--<< Node Handling end >>--




--- Return library table
return node_handling;
