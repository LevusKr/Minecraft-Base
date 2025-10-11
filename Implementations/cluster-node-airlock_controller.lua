--[[
    Airlock-Controller
    Airlock-Controller component of network cluster structure
    An Airlock-Controller acts as manager of an airlock, thus allowing control of it, e.g. opening and closing
    and receiving (and displaying) general information, e.g. current status
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-airlock_controller.log"; -- TODO: create new file at every startup?
--

-- Libraries and components
local codec = require("cluster/codec");
local colors = require("cluster/colors-hex");
local constants = require("cluster/constants");
local graphics = require("cluster/graphics");
local Logger = require("cluster/logger");
local Packet = require("cluster/network_packet");
local utils = require("cluster/utils");

local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local sides = require("sides");
local term = require("term");
local thread = require("thread");


local modem = component.modem;
local gpu = component.gpu;
local redstone = component.redstone;
local airlock_controller = component.airlock_controller;
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

local refresh_time = 0.5; --- Update interval (refresh rate) [seconds/update]


local airlock_controller_redstone_side = sides.left; --- Side where redstone is connected with airlock controller.
--

-- GUI stuff  TODO: rename
local res_x_backup, res_y_backup = gpu.getResolution();
local res_x, res_y = 48, 24; --- Screen resolution
local x, y = 1, 1; --- Position of drawing container
local width, height = res_x, res_y; -- Size of drawing container (here: fullscreen)

local gui_elements = {};
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if packet_request.port ~= constants.port.space_station then return; end



    local client = packet_request.sender;
    local operation = packet_request.data.operation;
    local payload = packet_request.data.payload;

    logger:info("Client '" .. tostring( client ) .. "' requested '" .. tostring( operation ) .. "' with payload '" .. tostring( payload ) .. "'");



    local response = {
        success = false,
        result = "Undefined"
    };


    if operation == "toggle" then

        response.success, response.result = toggle();

    elseif operation == "open" then

        response.success, response.result = open();

    elseif operation == "close" then

        response.success, response.result = close();

    elseif operation == "query" then

        response.success, response.result = is_open();

    end



    local send_success, send_result = packet_request:send_response( response );

    if send_success then
        logger:info("Response to client '"  .. tostring( client ) ..  "': '" .. tostring( response.success ) .. " - " .. tostring( response.result ) .. "'\n");
    else
        logger:error("Response to client '"  .. tostring( client ) ..  "' couldn't be sent: " .. tostring( send_result ) .. "\n");
    end



    --- Add event to event log and redraw   TODO: avoid redrawing after each, atm is needed, otherwise text overflows at top for some fucking reason
    gui_elements.log_events:log_add("Requested '" .. tostring( operation ) .. "': " .. tostring( response.result ));
    gui_elements.log_events:redraw();

end

--- Sends internal data to Core, passed through by Common Node via internal_data event
function data_send(data)
    
    event.push("internal_data", codec.encode( data )); -- TODO: data size and type etc.
    
end

--<< Data Handling end >>--




--<< Display Functions >>--

--- Sets up the gui and initialize elements
function display_setup()

    term.clear();





    --[[ GUI elements init ]]--

        --- Main container holding all gui elements
        gui_elements.container_main = graphics.container(
            x,
            y,
            res_x,
            res_y,
            0,
            nil,
            0x0
        );




        --- Title of program
        gui_elements.label_title = graphics.label(
            x,
            y,
            res_x,
            1,
            "AIRLOCK CONTROLLER DISPLAY",
            colors.primary,
            0xFFFFFF
        );

        gui_elements.container_main:child_add( gui_elements.label_title );





        --[[ EVENT LOG ]]--

            local log_events_width = width;
            local log_events_height = height / 4;
            local log_events_x = x;
            local log_events_y = (y + res_y - log_events_height);

            gui_elements.log_events = graphics.log(
                log_events_x,
                log_events_y,
                log_events_width,
                log_events_height,
                "Latest Events:",
                colors.primary,
                0x4B4B4B,
                0xFFFFFF
            );


            gui_elements.container_main:child_add( gui_elements.log_events );

        --[[ EVENT LOG END ]]--





        --[[ TOGGLE BUTTON ]]--

            --- Callback for toggle button
            local function button_toggle_callback(self, x, y, button, user)

                local success, result = toggle();


                --- Add log in appropriate color to event log and redraw
                if success then

                    gui_elements.log_events:log_add(tostring( user ) .. " " .. tostring( result ) .. " airlock.");

                else

                    gui_elements.log_events:log_add("Error: '" .. tostring( result ) .. "'", colors.failure);

                end

                gui_elements.log_events:redraw();

            end

            local button_toggle_width = width / 2;
            local button_toggle_height = height / 5;
            local button_toggle_x = x + width / 2  -  button_toggle_width / 2;
            local button_toggle_y = y + height / 2  -  button_toggle_height;

            local button_toggle_color = is_open() and colors.failure or colors.success;

            gui_elements.button_toggle = graphics.button(
                button_toggle_x,
                button_toggle_y,
                button_toggle_width,
                button_toggle_height,
                "Toggle",

                button_toggle_color,
                button_toggle_color,
                colors.foreground,
                button_toggle_callback
            );


            gui_elements.container_main:child_add( gui_elements.button_toggle );

        --[[ TOGGLE BUTTON END ]]--





        --[[ STATUS LABEL ]]--

            local label_status_width = 6;
            local label_status_height = 1;
            local label_status_x = width / 2 - label_status_width / 2;
            local label_status_y = button_toggle_y / 2;

            local label_status_text = is_open() and "|<  >|" or ">||<";
            local label_status_color = is_open() and colors.failure or colors.success;
        
            gui_elements.label_status = graphics.label(
                label_status_x,
                label_status_y,
                label_status_width,
                label_status_height,
                label_status_text,

                colors.black, --- Background
                label_status_color --- Label
            );


            gui_elements.container_main:child_add( gui_elements.label_status );

        --[[ STATUS LABEL END ]]--

    --[[ GUI elements init end ]]--





    --- Disable printing to avoid printing straight into gui, but allow the startup/shutdown logs to be printed (see display_stop)
    logger.print = false;
    logger.print_debug = false;


    --- Set touch mode to inverted so no sneak-clicking is needed for touch-activating the screen
    component.screen.setTouchModeInverted( true );



    --- Draw all elements to screen for the very first time and build element tree
    gui_elements.container_main:init();

end

--- Cleans up the gui and prepares for shutdown
function display_stop()

    if gui_elements.container_main then
        gui_elements.container_main:destroy();
    end


    --- Restore old print values to enable shutdown log printing
    logger.print = log_print;
    logger.print_debug = log_debug;


    component.screen.setTouchModeInverted( false );

end

--- Draws the gui to screen
function display_draw()

    --[[ GUI elements draw ]]--

        --[[ TOGGLE BUTTON ]]--

            gui_elements.button_toggle.color_selected = (
                is_open()
                    and colors.failure
                    or colors.success
            );

            gui_elements.button_toggle:redraw();

        --[[ TOGGLE BUTTON END ]]--




        --[[ STATUS LABEL ]]--

            gui_elements.label_status.text =
                is_open()
                and "|<  >|"
                or ">||<"
            ;

            gui_elements.label_status.color_label =
                is_open()
                and colors.failure
                or colors.success
            ;

            gui_elements.label_status:redraw();

        --[[ STATUS LABEL END ]]--

    --[[ GUI elements draw end ]]--

end

--- Executes data gathering and calls 'display_draw' function
function display_loop()

    display_draw();

end

--<< Display Functions end >>--




--<< Node Functions >>--

--- Toggle airlock via redstone
function toggle()

    local success, result = false, "Redstone Failure";


    local redstone_before = redstone.getOutput( airlock_controller_redstone_side );
    local redstone_level = 15 - redstone_before;

    local was_open = is_open();

    redstone.setOutput(airlock_controller_redstone_side, redstone_level);
    os.sleep(0.05)

    local is_open = is_open();


    --- Set result according to toggling success (old state ~= new state)
    success = was_open ~= is_open;

    if success then

        result =
            is_open
            and "Opened"
            or "Closed"
        ;

    else

        --- If output redstone level is off from actual level, there is an error with redstone wiring, most likely some external source powering the line (or spam toggling)
        local redstone_correct = redstone.getInput( airlock_controller_redstone_side ) == redstone_level;
        if not redstone_correct then

            result = "Redstone Interference";

        end

    end



    return success, result;

end

--- Open airlock via redstone
function open()

    if not is_open() then

        return toggle();

    end

    return true, "Already open";

end

--- Close airlock via redstone
function close()

    if is_open() then

        return toggle();

    end

    return true, "Already closed";

end

--- Whether airlock is open
function is_open()

    local success = airlock_controller.isOpen();
    local result =
        success
        and "Open"
        or "Closed"
    ;

    return success, result;

end

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

--- Main loop function, executed once every 'refresh_time' seconds
function loop()

    display_loop();

    data_send{
        is_open = is_open()
    };

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
            -- shutdown();
        end

    logger:info("Done.\n");
    --- Check for connection end



    --- Configure modem
    logger:info("Configuring modem...");

        modem.open( constants.port.space_station );
            logger:info("Modem port 'MAIN:" .. constants.port.main .. "' opened.\n");

    logger:info("Done.\n");
    --- Configure modem end



    --- Register event handlers
    logger:info("Registering event handlers...");

        event.listen("cluster_data", data_handle);
            logger:info("Listener 'cluster_data' registered.");

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

        modem.close( constants.port.space_station );
            logger:info("Modem port 'MAIN:" .. constants.port.main .. "' closed.");

    logger:info("Done.\n");
    --- Configure modem end



    --- Unregister event handlers
    logger:info("Unregistering event handlers...");

        event.ignore("cluster_data", data_handle);
            logger:info("Listener 'cluster_data' unregistered.");

    logger:info("Done.\n");
    --- Unregister event handlers end



    --- Stop loop
    logger:info("Stopping loop...");

        event.cancel(timer_loop);

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
    -- logger:transfer();
    running = false;

    os.exit(0);


    -- TODO: tell common node to disconnect?
end

--<< Main Functions end >>--




startup();

local success, result = thread.waitForAny({thread_interrupt_handler});

shutdown();