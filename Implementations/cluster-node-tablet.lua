--[[
    Control-Tablet
    Control-Tablet component of network cluster structure
    The Control-Tablet acts as interface for the core, thus being connected to the core
    and receiving (and displaying) general information, e.g. statuses of nodes
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-tablet.log";
--

-- Libraries and components
local codec = require("cluster/codec");
local colors = require("cluster/colors-hex")
local constants = require("cluster/constants");
local graphics = require("cluster/graphics")
local Logger = require("cluster/logger");
local Packet = require("cluster/network_packet");
local utils = require("cluster/utils");
local utils_string = require("cluster/utils-string");
local utils_sound = require("cluster/utils-sound");

local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local term = require("term");
local thread = require("thread");


local modem = component.modem;
local gpu = component.gpu;
--

-- Variables and constants
local logger = nil;
local log_print = true;
local log_debug = true;
local log_verbose = true;
local log_buffer = true;

local hostname = nil;

local timer_loop = 0;
local thread_interrupt_handler = nil;

local refresh_time = 0.25; --- Update interval (refresh rate) [seconds/update]
--

-- Data tables
local nodes = {}; --- Node list received via Core's data broadcast
local nodes_data = {}; --- Extracted data to avoid deep nesting in 'nodes' table
local nodes_status = {}; --- Status of Nodes (connected, active, color etc.)
local nodes_count = 0;

local node_selected = {};
--

-- GUI stuff  TODO: rename
local res_x_backup, res_y_backup = gpu.getResolution();
local res_x, res_y = 80, 25; --- Screen resolution
local x, y = 2, 2; --- Position of drawing container
local width, height = res_x - 2, res_y - 2; -- Size of drawing container (here: fullscreen)

local gui_elements = {};
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
local function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if (packet_request.port ~= constants.port.main_data) then return; end


    --- Handle nodes and nodes' data broadcast from core here
    if packet_request.port == constants.port.main_data then

        nodes = packet_request.data.nodes or nodes;
        nodes_data = packet_request.data.nodes_data or nodes_data;

        return;

    end


    local client = packet_request.sender;
    local operation = packet_request.data.operation;
    local payload = packet_request.data.payload;

    logger:info("Client '" .. tostring( client ) .. "' requested '" .. tostring( operation ) .. "' with payload '" .. tostring( payload ) .. "'");



    local response = {
        success = false,
        result = "Undefined"
    };


    if operation == "" then

    end



    local send_success, send_result = packet_request:send_response( response );

    if send_success then
        logger:info("Response to client '"  .. tostring( client ) ..  "': '" .. tostring( response.success ) .. " - " .. tostring( utils_string.dotate(codec.encode(response.result), 100) ) .. "'\n");
    else
        logger:error("Response to client '"  .. tostring( client ) ..  "' couldn't be sent: " .. tostring( send_result ) .. "\n");
    end

end

--- Sends internal data to Core, passed through by Common Node via internal_data event
function data_send(data)

    event.push("internal_data", data); -- TODO: data size and type etc.

end


local function event_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if packet_request.port ~= constants.port.event then return; end


    local _event = packet_request.data.event;
    local event_payload = packet_request.data.payload;


    if _event == constants.event.node_connected then

        utils_sound.const( constants.sound.info );

        gui_elements.log_events:log_add("Node '" .. tostring( event_payload.name ) .. "' connected.");

    elseif _event == constants.event.node_activated then

        utils_sound.const( constants.sound.success );

        gui_elements.log_events:log_add("Node '" .. tostring( event_payload.name ) .. "' activated.");

    elseif _event == constants.event.node_deactivated then

        utils_sound.const( constants.sound.failure );

        gui_elements.log_events:log_add("Node '" .. tostring( event_payload.name ) .. "' deactivated.");

    elseif _event == constants.event.node_disconnected then

        utils_sound.const( constants.sound.severe );

        gui_elements.log_events:log_add("Node '" .. tostring( event_payload.name ) .. "' disconnected.");

    elseif _event == constants.event.node_alarmed then

        utils_sound.const( constants.sound.error );

        gui_elements.log_events:log_add("Node '" .. tostring( event_payload.name ) .. "' alarmed.");

    end

end

--<< Data Handling end >>--




--<< Display Functions >>--

--- Sets up the gui and initialize elements
function display_setup()

    term.clear();

    buffer = gpu.allocateBuffer();
    gpu.setActiveBuffer( buffer );





    --[[ GUI elements init ]]--

        --- Main container holding all gui elements
        gui_elements.container_main = graphics.container(
            x,
            y,
            width,
            height,
            1,
            "CONTROL TABLET INTERFACE",
            0x0
        );





        --[[ NODES LIST ]]--

            local list_nodes_width = width / 3;
            local list_nodes_height = 9 + 1;
            local list_nodes_x = (width / 5  -  list_nodes_width / 2);
            local list_nodes_y = (height / 2  -  list_nodes_height / 1.5);

            gui_elements.list_nodes = graphics.list(
                list_nodes_x,
                list_nodes_y,
                list_nodes_width,
                list_nodes_height,
                1,
                "Nodes:",

                colors.primary, --- Background
                colors.blue, --- Selected
                colors.foreground, --- Label
                colors.border, --- Border
                colors.black, --- Border background
                colors.foreground, --- Border label

                function(self)

                    -- TODO: mark current node as selected (for later opening menu belonging to selected node)
                    node_selected = {
                        name = self.entries[ self.index ].label,
                        address = self.entries[ self.index ].value
                    };

                    gui_elements.log_events:log_add("Node selected: " .. tostring( node_selected.name ));

                end
            );

            for i = 0, list_nodes_height - 3 do

                gui_elements.list_nodes:entry_add("...");

            end


            gui_elements.container_main:child_add( gui_elements.list_nodes );

        --[[ NODES LIST END ]]--





        --[[ EVENT LOG ]]--

            local log_events_width = width / 2;
            local log_events_height = height / 5;
            local log_events_x = x;
            local log_events_y = y + height - log_events_height - 1;
            local log_events_label = "Latest Events:";

            gui_elements.log_events = graphics.log(
                log_events_x,
                log_events_y,
                log_events_width,
                log_events_height,
                log_events_label,

                colors.primary, --- Background
                colors.border, --- Border
                colors.foreground --- Border label
            );


            gui_elements.container_main:child_add( gui_elements.log_events );

        --[[ EVENT LOG END ]]--





        --[[ CONTROL CONTAINER ]]--

            local container_control_width = width / 4;
            local container_control_height = height / 2;
            local container_control_x = (width / 1.15  -  container_control_width / 2);
            local container_control_y = (height / 2 - container_control_height / 2);

            gui_elements.container_control = graphics.container(
                container_control_x,
                container_control_y,
                container_control_width,
                container_control_height,
                1,
                "Control: N/A",

                colors.primary, --- Background
                colors.border, --- Border
                colors.background, --- Border background
                colors.foreground --- Border label
            );


            gui_elements.container_main:child_add( gui_elements.container_control );




            local label_width = gui_elements.container_control.width;
            local label_height = 1;
            local label_x = 1;
            local label_y = gui_elements.container_control.height;
            local label_spread = 4;

            local label_color_background = colors.blue;




            --[[ ADDRESS LABEL ]]--

                gui_elements.label_address = graphics.label(
                    label_x,
                    label_y / (label_spread / 1),
                    label_width,
                    label_height + 1,
                    "Address:\nN/A",

                    label_color_background, --- Background
                    colors.foreground, --- Label
                    "CENTER", --- Alignment
                    "TOP" --- Alignment Vertical
                );


                gui_elements.container_control:child_add( gui_elements.label_address );

            --[[ ADDRESS LABEL END ]]--




            --[[ STATUS LABEL ]]--

                gui_elements.label_status = graphics.label(
                    label_x,
                    label_y / (label_spread / 2),
                    label_width,
                    label_height,
                    "Status: N/A",

                    label_color_background, --- Background
                    colors.foreground --- Label
                );

                gui_elements.container_control:child_add( gui_elements.label_status );

            --[[ STATUS LABEL END ]]--




            --[[ DATA LABEL ]]--

                gui_elements.label_data = graphics.label(
                    label_x,
                    label_y / (label_spread / 3),
                    label_width,
                    label_height,
                    "Data: N/A",

                    label_color_background, --- Background
                    colors.foreground, --- Label

                    _,
                    _,

                    {
                        popup = false,
                        data = "Not Available"
                    }
                );

                gui_elements.container_control:child_add( gui_elements.label_data );

            --[[ DATA LABEL END ]]--




            --[[ REBOOT BUTTON ]]--

                local function button_reboot_callback(self)

                    if not node_selected then
                        return;
                    end


                    local send_success, send_result = Packet.create(
                        modem.address,
                        node_selected.address,
                        constants.port.main,
                        constants.packet.disconnect,
                        {
                            reason = "Remote reboot",
                            reboot = true
                        }
                    ):send();

                    if send_success then
                        gui_elements.log_events:log_add("Node rebooted: " .. tostring( node_selected.name ));
                    else
                        gui_elements.log_events:log_add("Node couldn't be rebooted: " .. tostring( send_result ));
                    end


                    self:redraw();

                    event.timer(1.5, function()

                        self.status = false;
                        self:redraw();

                    end, 1); -- TODO: do this in library already

                end

                gui_elements.button_reboot = graphics.button(
                    label_x,
                    label_y / (label_spread / 4),
                    label_width,
                    label_height,
                    "REBOOT",

                    colors.red, --- Background
                    colors.green, --- Selected
                    colors.foreground, --- Label

                    button_reboot_callback
                );

                gui_elements.container_control:child_add( gui_elements.button_reboot );

            --[[ REBOOT BUTTON END ]]--

        --[[ CONTROL CONTAINER END ]]--

    --[[ GUI elements init end ]]--





    --- Disable printing to avoid printing straight into gui, but allow the startup/shutdown logs to be printed (see display_stop)
    print_backup = logger.print;
    print_debug_backup = logger.print_debug;
    logger.print = false;
    logger.print_debug = false;



    --- Draw all elements to screen for the very first time and build tree
    gui_elements.container_main:init();


    gpu.bitblt();
    gpu.setActiveBuffer( buffer );

end

--- Cleans up the gui and prepares for shutdown
function display_stop()

    if gui_elements.container_main then

        gui_elements.container_main:destroy();

    end


    --- Restore old print values to enable shutdown log printing
    logger.print = print_backup;
    logger.print_debug = print_debug_backup;


    gpu.freeBuffer( buffer );

end

--- Executes data gathering and calls 'display_draw' function
function display_loop()

    nodes_count = 0;

    gui_elements.list_nodes.entries = {};


    for node_address, node in pairs( nodes ) do

        nodes_count = nodes_count + 1;

        
        nodes_status[ node_address ] = {};
        local node_status = "UNKNOWN";
        local node_color = colors.red_dark;

    
        nodes_status[ node_address ].active = node.status;
        nodes_status[ node_address ].connected = node.connected;
        nodes_status[ node_address ].status = node_status;
        nodes_status[ node_address ].color = node_color;

        if node.connected then

            if node.status then

                node_status = "ACTIVE";
                node_color = colors.green;

            else

                node_status = "INACTIVE";
                node_color = colors.yellow;

            end

        else

            node_status = "DISCONNECTED";
            node_color = colors.red;

        end

        nodes_status[ node_address ].status = node_status;
        nodes_status[ node_address ].color = node_color;





        if node.name:match("airlock_controller") then

            if nodes_data[ node_address ] then

                local is_open = nodes_data[ node_address ].is_open;

                if is_open then

                    node_status = "ALARMING";
                    node_color = colors.orange;

                    -- TODO: handle this async since this lags holy shit
                    computer.beep(200, 0.8);
                    computer.beep(800, 0.5);

                end

            end

        end

        nodes_status[ node_address ].status = node_status;
        nodes_status[ node_address ].color = node_color;

        gui_elements.list_nodes:entry_add(utils_string.dotate(node.name, gui_elements.list_nodes.width), node_address, node_color);

    end



    display_draw();

end

--- Draws the gui to screen
function display_draw()

    local queue_redraw = {};
    gpu.setActiveBuffer( buffer );



    local node_name = node_selected.name;
    local node_address = node_selected.address;
    local node_data = nodes_data[ node_address ] or {};
    local node_status = nodes_status[ node_address ] or {};


    --[[ GUI elements draw ]]--

        --[[ NODES LIST ]]--

            gui_elements.list_nodes.height = nodes_count + 1;

            --gui_elements.list_nodes:redraw();
            queue_redraw[ #queue_redraw + 1 ] = "list_nodes";

        --[[ NODES LIST END ]]--




        --[[ EVENT LOG ]]--

            --gui_elements.log_events:redraw();
            queue_redraw[ #queue_redraw + 1 ] = "log_events";

        --[[ EVENT LOG END ]]--




        --[[ CONTROL CONTAINER ]]--

            for i, child in pairs( gui_elements.container_control.children ) do

                if child.type == "Border" then

                    local border = child;

                    --- Retrieve border's label and update name of selected node
                    border.children[1].text = "Control: " .. tostring(node_name or "N/A");

                end

            end

            --gui_elements.container_control:redraw();
            queue_redraw[ #queue_redraw + 1 ] = "container_control";




            --[[ ADDRESS LABEL ]]--

                gui_elements.label_address.text = "Address:\n" .. utils_string.dotate(tostring( node_address ) or "N/A", gui_elements.label_address.width);

                --gui_elements.label_address:redraw();
                queue_redraw[ #queue_redraw + 1 ] = "label_address";

            --[[ ADDRESS LABEL END ]]--




            --[[ STATUS LABEL ]]--

                gui_elements.label_status.text = "Status: " .. tostring(node_status.status or "N/A");
                gui_elements.label_status.color_label = node_status.color;

                --gui_elements.label_status:redraw();
                queue_redraw[ #queue_redraw + 1 ] = "label_status";

            --[[ STATUS LABEL END ]]--




            --[[ DATA LABEL ]]--

                gui_elements.label_data.text = "Data: " .. utils_string.dotate(codec.encode( node_data ) or "N/A", gui_elements.label_data.width);

                --gui_elements.label_data:redraw();
                queue_redraw[ #queue_redraw + 1 ] = "label_data";

            --[[ DATA LABEL END ]]--

        --[[ CONTROL CONTAINER END ]]--



        --- Collectively redraw elements
        --gui_elements.container_main:redraw();
        for i, element in pairs( queue_redraw ) do

            gui_elements[ element ]:redraw();

        end

    --[[ GUI elements draw end ]]--


    gpu.bitblt();
    gpu.setActiveBuffer( buffer );

end

--<< Display Functions end >>--




--<< Node Functions >>--



--<< Node Functions end >>--




--<< Threads >>-

--- Handle program interruption. Every task depends on boolean 'running', so when running is false they automatically clean up and exit
local function interrupt_handler()

    while running do

        event.pull("interrupted");
        running = false;

    end

end

--<< Threads end >>--




--<< Main Functions >>--

--- Initialize logger
local function init_log()

    local logger_init_success, logger_init_result = Logger.create(
        hostname,
        file_log,
        log_print,
        log_debug,
        log_verbose,
        log_buffer
    );


    if not logger_init_success then

        error("Error whilst initializing logger: " .. tostring( logger_init_result ));

    end


    logger = logger_init_result;

end

--- Main loop function, executed once every second
function loop()

    display_loop();

    --data_send(launch_controller_data);

end

--- Main startup function, executed once at startup
function startup()

    local time_startup = computer.uptime();


    running = true;

    hostname = utils.internal.hostname();

    init_log();



    term.clear();
    logger:info("----- STARTUP -----", false);
    logger:info("Starting up...\n");



    --- Check for connection
    logger:info("Checking for connection to Core...");

        if not os.getenv( constants.env.connected ) then
            logger:error("Not connected to Core.");
            --shutdown();
        end

    logger:info("Done.\n");
    --- Check for connection end



    --- Implement
    logger:info("Implement");

        --

    logger:info("Done.\n");
    --- Implement end

    
    
    --- Configure modem
    logger:info("Configuring modem...");

        modem.open( constants.port.main_data );
            logger:info("Modem port 'MAIN_DATA:" .. constants.port.main_data .. "' opened.\n");
        modem.open( constants.port.event );
            logger:info("Modem port 'EVENT:" .. constants.port.event .. "' opened.\n");

    logger:info("Done.\n");
    --- Configure modem end



    --- Register event handlers
    logger:info("Registering event handlers...");

        event.listen("cluster_data", data_handle);
            logger:info("Listener 'cluster_data' registered.");
        event.listen("cluster_event", event_handle);
            logger:info("Listener 'cluster_event' registered.");

    logger:info("Done.\n");
    --- Register event handlers end



    --- Start loop
    logger:info("Starting loop...");

        timer_loop = event.timer(refresh_time, loop, math.huge);

    logger:info("Done.\n");



    --- Start threads
    logger:info("Starting threads...");

        thread_interrupt_handler = thread.create(interrupt_handler);
            logger:info("Thread 'interrupt_handler' started.");

    logger:info("Done.\n ");
    --- Start threads end



    --- Setup GUI
    logger:info("Setting up GUI...");

        gpu.setResolution(res_x, res_y);
            logger:info("Screen Resolution set to '" .. res_x .. "x" .. res_y .. "'");

        display_setup();

    logger:info("Done.\n ");
    --- Setup GUI end



    local time_startup_finished = computer.uptime() - time_startup;
    logger:info("Successfully started up in " .. time_startup_finished .. " seconds.\n\n");

end

--- Main shutdown function, executed once at shutdown
function shutdown()

    local time_shutdown = computer.uptime();


    logger:info("----- SHUTDOWN -----", false);
    logger:info("Shutting down...\n");



    --- Configure modem
    logger:info("Configuring modem...");

        modem.close( constants.port.main );
            logger:info("Modem port 'MAIN:" .. constants.port.main .. "' closed.");

    logger:info("Done.\n");
    --- Configure modem end



    --- Unregister event handlers
    logger:info("Unregistering event handlers...");

        event.ignore("cluster_data", data_handle);
            logger:info("Listener 'cluster_data' unregistered.");
        event.ignore("cluster_event", event_handle);
            logger:info("Listener 'cluster_event' unregistered.");

    logger:info("Done.\n");
    --- Unregister event handlers end



    --- Stop loop
    logger:info("Stopping loop...");

        event.cancel( timer_loop );

    logger:info("Done.\n");
    --- Stop loop end



    --- Stop GUI
    logger:info("Stopping GUI...");

        gpu.setResolution(res_x_backup, res_y_backup);
            logger:info("Screen Resolution set to '" .. res_x_backup .. "x" .. res_y_backup .. "'");

        display_stop();

    logger:info("Done.\n ");
    --- Stop GUI end



    local time_shutdown_finished = computer.uptime() - time_shutdown;
    logger:info("Successfully shut down in " .. time_shutdown_finished .. " seconds.");




    logger:close();
    logger:transfer();



    running = false;


    os.exit(0);


    -- TODO: tell common node to disconnect?
end

--<< Main Functions end >>--




startup();

local success, result = thread.waitForAny( { thread_interrupt_handler } );

shutdown();