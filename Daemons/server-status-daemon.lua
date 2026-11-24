--[[
    Server-Status-Daemon
    This Server-Status-Daemon will run on startup and check various conditions, e.g. network connection or power supply
    and display those states via an installed Light Board in the server rack.
    These states can also be toggled via an installed Switch Board.
--]]


-- Files and configurations
--

-- Libraries and components
local constants = require("cluster/constants");

local component = require("component");
local os = require("os");
local event = require("event");


local light_board = component.isAvailable("light_board") and component.light_board or nil;
local switch_board = component.isAvailable("switch_board") and component.switch_board or nil;
--

-- Variables and Constants
local timer_update_publishing_status = nil;
--

-- Data tables

--




--<< Daemon Functions >>--

function is_connected()

    return os.getenv( constants.env.connected ) == "true";

end

--- Update connection indicator according to switch state and actual node state
function update_connection_status(event, address, switch_index, switch_state)

    print(event, address, switch_index, switch_state)

    if switch_index == 1 then

        local success, result = os.execute("rc cluster-node " .. (switch_state and "connect" or "disconnect"));
        print(success, result)

    end


    if light_board then

        light_board.setActive(1, event == "cluster_connect"); --- Light for cluster connection status
        light_board.setColor(1, event == "cluster_connect" and 0x00B600 or 0xFF0000); --- Color for cluster connection status light

    end

end


function is_publishing()

    return os.getenv( constants.env.publishing ) == "true";

end

--- Update publishing indicator according to switch state and actual node state
function update_publishing_status(_, _, switch_index, switch_state)

    if switch_index == 2 then

        local success = os.execute("rc cluster-node update_var publishing " .. tostring( switch_state ));

    end


    if light_board then

        light_board.setActive(2, switch_state ~= nil and switch_state or is_publishing()); --- Light for cluster publishing status
        light_board.setColor(2, (switch_state ~= nil and switch_state or is_publishing()) and 0x00B600 or 0xFF0000); --- Color for cluster publishing status light

    end

end

--<< Daemon Functions end >>--




--<< RC Handling >>--

--- RC API start function - Listen for events to update light board
function start()

    update_connection_status();

    event.listen("cluster_connect", update_connection_status);
    event.listen("cluster_disconnect", update_connection_status);


    update_publishing_status();

    timer_update_publishing_status = event.timer(5, update_publishing_status, math.huge);


    event.listen("switch_flipped", update_connection_status);
    event.listen("switch_flipped", update_publishing_status);

    local running = true;

    while running do

        event.pull("interrupted");
        running = false;

        stop();

    end

end

--- RC API stop function - XXX
function stop()

    event.ignore("cluster_connect", update_connection_status);
    event.ignore("cluster_disconnect", update_connection_status);


    event.cancel(timer_update_publishing_status);


    event.ignore("switch_flipped", update_connection_status);
    event.ignore("switch_flipped", update_publishing_status);

end

start();

--<< RC Handling >>--