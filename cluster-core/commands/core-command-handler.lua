local core_command_handler = {};


-- Files and Configurations

--

-- Libraries and components
local utils_string = require("cluster/utils-string");
--

-- Variables and constants

--

-- Data tables
core_command_handler.command_map = {
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



        for _, alias in pairs( command_data.aliases ) do
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

inject_command_map( core_command_handler.command_map );
--



--- Command handler that receives terminal input and executes corresponding command
function core_command_handler.command_handler(command_string)

    if not command_string or command_string == "" then
        return;
    end


    local commands = utils_string.split( command_string );

    logger:debug("Command received: " .. serialization.serialize( commands ));

    local command = commands[1];
    local command_data = core_command_handler.command_map[ command ];

    if not command_data then
        return logger:error("Command '" .. tostring( command ) .. "' not found.");
    end

    --- If the command is an alias, use the actual command for further processing
    if type( command_data ) == "string" then
        command = command_data;
        command_data = core_command_handler.command_map[ command ];
    end


    if command == "help" then

        -- TODO: display general help message

        if #commands > 1 then

            logger:info(command_data.description);
            logger:info("Aliases: " .. serialization.serialize( command_data.aliases ));

        end

    elseif command == "stop" then

        logger:warn("Exiting...");
        running = false;

    elseif command == "memory" then

        logger:info("Memory Usage: " .. tostring(computer.usedMemory()/1000).. "/" .. tostring(computer.totalMemory()/1000) .. " KB ("
            .. string.format("%.2f", tostring(computer.usedMemory()/computer.totalMemory()*100)) .. "%)");

        if commands[2] then
            logger:flush();

            logger:info("Memory Usage: " .. tostring(computer.usedMemory()/1000).. "/" .. tostring(computer.totalMemory()/1000) .. " KB ("
                .. string.format("%.2f", tostring(computer.usedMemory()/computer.totalMemory()*100)) .. "%)");
        end

    elseif command == "clear" then

        terminal:clear();

    elseif command == "node" then

        if commands[2] == "list" then

            --- List all nodes here, for serialization of a specific node, see below
            if #commands < 3 then

                logger:info(serialization.serialize(nodes.contents, true));

                return;

            end

        elseif commands[2] == "stop"
            or commands[2] == "shutdown" then

            for name, address in pairs( nodes_by_name ) do

                node_shutdown(address, "CLI shutdown"); -- TODO: process return values

            end

            return

        elseif commands[2] == "restart"
            or commands[2] == "reboot" then

            for name, address in pairs( nodes_by_name ) do

                node_reboot(address, "CLI reboot"); -- TODO: process return values

            end

            return

        end


        --- Can be either name or address, but since this is a CLI, it will be a name most of the time anyway
        local _node = commands[2];
        local node = nodes.contents[ _node ];

        if node then

            if commands[3] == "list"
                or commands[3] == "ls"
                or commands[3] == "info"
                or commands[3] == "status" then

                if #commands < 4 then

                    logger:info(serialization.serialize(node, true));

                    return;

                end

                logger:info(_node .. ": " .. commands[4] .. ": " .. tostring(node[ commands[4] ]));

            elseif commands[3] == "start"
                or commands[3] == "boot"
                or commands[3] == "wakeup"
                or commands[3] == "wake" then

                local success, result = node_start(node.address, "CLI start");

                if success then

                    logger:info("Node '" .. node.name .. "' started.");

                else

                    logger:warn("Node '" .. node.name .. "' could not be started: " .. tostring( result ));

                end

            elseif commands[3] == "stop"
                or commands[3] == "shutdown" then

                local success, result = node_shutdown(node.address, "CLI shutdown");

                if success then

                    logger:info("Node '" .. node.name .. "' stopped.");

                else

                    logger:warn("Node '" .. node.name .. "' could not be stopped: " .. tostring( result ));

                end

            elseif commands[3] == "reboot"
                or commands[3] == "restart"
                or commands[3] == "rb" then

                local success, result = node_reboot(node.address, "CLI reboot");

                if success then

                    logger:info("Node '" .. node.name .. "' rebooted.");

                else

                    logger:warn("Node '" .. node.name .. "' could not be rebooted: " .. tostring( result ));

                end

            elseif commands[3] == "disconnect" then

                local success, result = node_disconnect(node.address, "CLI disconnect");

                if success then

                    logger:info("Node '" .. node.name .. "' disconnected.");

                else

                    logger:warn("Node '" .. node.name .. "' could not be disconnected: " .. tostring( result ));

                end

            end

        else

            logger:error("Node '" .. tostring( _node ) .. "' not found.");

        end

    else

        logger:error("Command '" .. tostring( command_string ) .. "' not found.");

    end


    return true;

end

--- Tab completer that receives terminal input and provides suggestions based on command map
function core_command_handler.tab_completer(command_line, position)

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
        suggestions = find_suggestions(core_command_handler.command_map, part_to_complete);

    elseif num_parts >= 2 and parts[1] == "node" then

        --- Completing 'node <subcommand>' or 'node <nodename>'
        if num_parts == 2 then

            --- Suggest 'list'
            if string.sub("list", 1, #part_to_complete) == part_to_complete then
                table.insert(suggestions, "list")
            end

            --- Suggest node names for using with further sub-commands
            for name, _ in pairs(nodes_by_name) do
                if name:sub(1, #part_to_complete) == part_to_complete then
                    table.insert(suggestions, name)
                end
            end

        elseif num_parts == 3 then

            local node_name = parts[2];

            --- Check if the second part is a valid node name
            if nodes_by_name[ node_name ] then
                --- It is, so we are completing the sub-commands for nodes
                suggestions = find_suggestions(core_command_handler.command_map.node["<node>"], part_to_complete);
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
return core_command_handler;