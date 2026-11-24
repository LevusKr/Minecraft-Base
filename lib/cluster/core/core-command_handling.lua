--[[
    Cluster-Core - Command Handling
    TODO: description
--]]


local core_command_handling = {};


-- Files and Configurations

--

-- Libraries and components
local shared_data = require("cluster/core/core-shared_data");
local node_handling = require("cluster/core/core-node_handling");

local utils_string = require("cluster/utils-string");

local computer = require("computer");
local serialization = require("serialization");
--

-- Variables and constants

--

-- Data tables
core_command_handling.command_map = {
    help = {
        description = "Show help message.",
        aliases = {
            "?",
            "h",
            "man"
        }
    },

    status = {
        description = "Show status.",
        aliases = {
            "i"
        }
    },

    stop = {
        description = "Stop the Core.",
        --usage = "stop",
        aliases = {
            "exit",
            "quit",
            "e",
            "q"
        }
    },

    memory = {
        description = "Show memory usage.",
        --usage = "memory",
        aliases = {
            "mem"
        }
    },

    clear = {
        description = "Clear terminal.",
        --usage = "clear",
        aliases = {
            "cl"
        }
    },

    node = {
        -- TODO: support the following structure by differentiating command data from subcommands
        ["<node>"] = {
            info = {
                aliases = {
                    "status"
                }
            },
            --status = "info",

            start = {},

            stop = {},

            restart = {},

            connect = {},

            disconnect = {}
        }
    }
};

--- Add name to commands and add aliases to command map for quick reference without iterating all commands everytime
local function inject_command_map(map)

    --- If used recursively, possibly subcommands and their data!
    for command, command_data in pairs( map ) do

        --- If 'command_data' is no table, it is an alias (string) already referencing a parent command
        --- Or If 'command_data' is a table without named indexes but rather numeric indexes (aliases table)
        if type( command_data ) ~= "table" or #command_data > 0 then
            return;
        end



        --- If no name is defined, set name to command name (+ parent's name if present)
        map[ command ].name = map[ command ].name ~= nil
            and map[ command ].name
            or (map.name or "") .. command; --- Append subcommand name to parent's name  TODO: add space between but only if a parent name is present


        --- If no usage is defined, set usage to command name (+ parent's usage if present)
        map[ command ].usage = map[ command ].usage ~= nil
            and map[ command ].usage
            or (map.usage or "") .. command; --- Append subcommand name to parent's usage  TODO: add space between but only if a parent usage is present



        for _, alias in pairs( command_data.aliases or {} ) do
            ---@diagnostic disable-next-line: assign-type-mismatch
            map[ alias ] = command;
        end



        --- Add usage of 'node' command and it's present subcommands to command map
        if command == "node" then

            local usage_node = "node <all|$node> [";

            for subcommand, _ in pairs( command_data["<node>"] ) do

                usage_node = usage_node .. subcommand .. "|";

                command_data["<node>"][subcommand].usage = "node <all|$node> " .. subcommand;

            end

            --- Remove trailing '|' and add closing bracket
            map["node"].usage = usage_node:sub(1, #usage_node - 1) .. "]";

        end


        inject_command_map( command_data );

    end

end

inject_command_map( core_command_handling.command_map );
--



--- Command handler that receives terminal input and executes corresponding command
function core_command_handling.command_handler(command_string)

    if utils_string.is_null_or_empty(command_string) then
        return;
    end


    local command_string_parts = utils_string.split( command_string );

    shared_data.logger:debug("Command received: " .. serialization.serialize( command_string_parts ));

    local command = command_string_parts[1];
    local command_data = core_command_handling.command_map[ command ];

    if not command_data then
        return shared_data.logger:error("Command '" .. tostring( command ) .. "' not found.");
    end

    --- If the command is an alias, use the actual command for further processing
    if type( command_data ) == "string" then
        
        command = command_data;
        command_data = core_command_handling.command_map[ command ];

        if not command_data then
            return shared_data.logger:error("Command alias '" .. command .. "' could not be resolved.");
        end
    end


    if command == "help" then

        -- TODO: display general help message

        if #command_string_parts > 1 then

            shared_data.logger:info(command_data.description);
            shared_data.logger:info("Aliases: " .. serialization.serialize( command_data.aliases ));

        end

    elseif command == "status" then

        shared_data.logger:info(
            "Status:\n" ..
            "Running: " .. tostring(shared_data.running) .. "\n" ..
            "Core Address: " .. tostring(shared_data.address) .. "\n" ..
            "Core Port: " .. tostring(shared_data.port) .. "\n" ..
            "Nodes: " .. tostring(shared_data.nodes) .. "\n" ..
            "Nodes By Name: " .. tostring(shared_data.nodes_by_name) .. "\n" ..
            "Nodes Data: " .. tostring(shared_data.nodes_data) .. "\n" ..
            "Packet Queue: " .. tostring(shared_data.packet_queue) .. "\n");

    elseif command == "stop" then

        shared_data.logger:warn("Exiting...");
        shared_data.update_var_running( false );

    elseif command == "memory" then

        shared_data.logger:info("Memory Usage: " .. tostring(computer.usedMemory()/1000).. "/" .. tostring(computer.totalMemory()/1000) .. " KB ("
            .. string.format("%.2f", tostring(computer.usedMemory()/computer.totalMemory()*100)) .. "%)");

        if command_string_parts[2] then
            shared_data.logger:flush();

            shared_data.logger:info("Memory Usage: " .. tostring(computer.usedMemory()/1000).. "/" .. tostring(computer.totalMemory()/1000) .. " KB ("
                .. string.format("%.2f", tostring(computer.usedMemory()/computer.totalMemory()*100)) .. "%)");
        end

    elseif command == "clear" then

        shared_data.terminal:clear();

    elseif command == "node" then

        if command_string_parts[2] == "list" then

            --- List all nodes here, for serialization of a specific node, see below
            if #command_string_parts < 3 then

                shared_data.logger:info(serialization.serialize(shared_data.nodes.contents, true));

                return;

            end

        elseif command_string_parts[2] == "stop"
            or command_string_parts[2] == "shutdown" then

            for name, address in pairs( shared_data.nodes_by_name ) do

                node_handling.node_shutdown(address, "CLI shutdown"); -- TODO: process return values

            end

            return

        elseif command_string_parts[2] == "restart"
            or command_string_parts[2] == "reboot" then

            for name, address in pairs( shared_data.nodes_by_name ) do

                node_handling.node_reboot(address, "CLI reboot"); -- TODO: process return values

            end

            return

        end


        --- Can be either name or address, but since this is a CLI, it will be a name most of the time anyway
        local _node = command_string_parts[2];
        local node = shared_data.nodes.contents[ _node ];

        if node then

            if command_string_parts[3] == "list"
                or command_string_parts[3] == "ls"
                or command_string_parts[3] == "info"
                or command_string_parts[3] == "status" then

                if #command_string_parts < 4 then

                    shared_data.logger:info(serialization.serialize(node, true));

                    return;

                end

                shared_data.logger:info(_node .. ": " .. command_string_parts[4] .. ": " .. tostring(node[ command_string_parts[4] ]));

            elseif command_string_parts[3] == "start"
                or command_string_parts[3] == "boot"
                or command_string_parts[3] == "wakeup"
                or command_string_parts[3] == "wake" then

                local success, result = node_handling.node_start(node.address, "CLI start");

                if success then

                    shared_data.logger:info("Node '" .. node.name .. "' started.");

                else

                    shared_data.logger:warn("Node '" .. node.name .. "' could not be started: " .. tostring( result ));

                end

            elseif command_string_parts[3] == "stop"
                or command_string_parts[3] == "shutdown" then

                local success, result = node_handling.node_shutdown(node.address, "CLI shutdown");

                if success then

                    shared_data.logger:info("Node '" .. node.name .. "' stopped.");

                else

                    shared_data.logger:warn("Node '" .. node.name .. "' could not be stopped: " .. tostring( result ));

                end

            elseif command_string_parts[3] == "reboot"
                or command_string_parts[3] == "restart"
                or command_string_parts[3] == "rb" then

                local success, result = node_handling.node_reboot(node.address, "CLI reboot");

                if success then

                    shared_data.logger:info("Node '" .. node.name .. "' rebooted.");

                else

                    shared_data.logger:warn("Node '" .. node.name .. "' could not be rebooted: " .. tostring( result ));

                end

            elseif command_string_parts[3] == "disconnect" then

                local success, result = node_handling.node_disconnect(node.address, "CLI disconnect");

                if success then

                    shared_data.logger:info("Node '" .. node.name .. "' disconnected.");

                else

                    shared_data.logger:warn("Node '" .. node.name .. "' could not be disconnected: " .. tostring( result ));

                end

            end

        else

            shared_data.logger:error("Node '" .. tostring( _node ) .. "' not found.");

        end

    else

        shared_data.logger:error("Command '" .. tostring( command_string ) .. "' not found.");

    end


    return true;

end

--- Tab completer that receives terminal input and provides suggestions based on command map
function core_command_handling.tab_completer(command_line, position)

    local line_to_cursor = command_line:sub(1, position);
    local parts = utils_string.split(line_to_cursor);
    local num_parts = #parts;
    local suggestions = {};

    --- If the last character is a space, or the line is empty, we are completing a new word
    local is_completing_new_word = line_to_cursor:sub(-1) == " " or line_to_cursor == ""

    if is_completing_new_word then
        table.insert(parts, "");
        num_parts = num_parts + 1;
    end

    local part_to_complete = parts[ num_parts ];

    -- Helper to find suggestions in a table based on a prefix
    local function find_suggestions(map, prefix)
        local result = {};

        for key, value in pairs(map) do
            if key:sub(1, #prefix) == prefix then
                --- If the value is a string, use it instead of the matching key
                -- TODO: this autocompletes command aliases to the parent command, should we be doing this? better to fix command_handler
                table.insert(result, type(value) == "string" and value or key);
            end
        end

        return result;
    end

    --- Determine the context and provide suggestions
    if num_parts == 1 then

        --- Completing the root commands
        suggestions = find_suggestions(core_command_handling.command_map, part_to_complete);

    elseif num_parts >= 2 and parts[1] == "node" then

        --- Completing 'node <subcommand>' or 'node <nodename>'
        if num_parts == 2 then

            --- Suggest 'list'
            if string.sub("list", 1, #part_to_complete) == part_to_complete then
                table.insert(suggestions, "list")
            end

            --- Suggest node names for using with further sub-commands
            for name, _ in pairs(shared_data.nodes_by_name) do
                if name:sub(1, #part_to_complete) == part_to_complete then
                    table.insert(suggestions, name)
                end
            end

        elseif num_parts == 3 then

            local node_name = parts[2];

            --- Check if the second part is a valid node name
            if shared_data.nodes_by_name[ node_name ] then
                --- It is, so we are completing the sub-commands for nodes
                suggestions = find_suggestions(core_command_handling.command_map.node["<node>"], part_to_complete);
            end

        end

    end

    --- Format suggestions into full command lines that term.read expects
    if #suggestions > 0 then

        local formatted_suggestions = {};
        local prefix = "";

        if num_parts > 1 then
            --- Reconstruct the line up to the part being completed
            prefix = table.concat(parts, " ", 1, num_parts - 1) .. " ";
        end

        for _, suggestion in ipairs( suggestions ) do
            --- The hint should be the full line, ending with a space for convenience
            table.insert(formatted_suggestions, prefix .. suggestion .. " ");
        end


        return formatted_suggestions;

    end

    return {}; -- No suggestions

end




--- Return library table
return core_command_handling;