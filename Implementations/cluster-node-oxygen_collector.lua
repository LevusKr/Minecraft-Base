--[[
    Oxygen Collector
    Oxygen Collector component of network cluster structure
    A Oxygen Collector acts as graphical interface for multiple adjacent Galacticraft oxygen collectors, thus computing and displaying
    important and interesting information, e.g. current oxygen level, production rate etc.
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-oxygen_collector.log"; -- TODO: create new file at every startup?
--

-- Libraries and components
local codec = require("cluster/codec");
local colors = require("cluster/colors-hex");
local constants = require("cluster/constants");
local graphics = require("cluster/graphics");
local Logger = require("cluster/logger");
local Packet = require("cluster/network_packet");
local resources = require("cluster/resources");

local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local term = require("term");
local thread = require("thread");
local utils = require("cluster/utils");

local modem = component.modem;
local gpu = component.gpu;
local oxygen_collectors = {};
--local oxygen_collector = component.oxygen_collector;
--local tank_buffer = component.tank_controller;   TODO: implement support for small buffer tank before oxygen pipes to main tank
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

local refresh_time = 2.0; --- Update interval (refresh rate) [seconds/update]
--

-- Data tables
local oxygen_collectors_data = {};
--

-- GUI stuff  TODO: rename
local res_x_backup, res_y_backup = gpu.getResolution();
local res_x, res_y = 160, 50; --- Screen resolution
local x, y = 2, 2; --- Position of drawing container
local width, height = res_x - 2, res_y - 2; -- Size of drawing container (here: fullscreen)

local gui_elements = {};

local gui_buffer = nil;
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if packet_request.port ~= constants.port.oxygen then return; end



    local client = packet_request.sender;
    local operation = packet_request.data.operation;
    local query = packet_request.data.query;
    local options = packet_request.data.options or {};

    logger:info("Client '" .. tostring( client ) .. "' requested '"  .. tostring( operation ) .. "' with '"  .. tostring( query ) ..  "'\n");



    local response = {
        success = false,
        result = "Server busy"
    };


    local send_success, send_result = packet_request:send_response( response );

    if send_success then
        logger:info("Response to client '"  .. tostring( client ) ..  "': '" .. tostring( response.success ) .. " - " .. tostring( response.result ) .. "'\n");
    else
        logger:error("Response to client '"  .. tostring( client ) ..  "' couldn't be sent: " .. tostring( send_result ) .. "\n");
    end

end

--- Sends internal data to Core, passed through by Common Node via internal_data event
function data_send(data)

    event.push("internal_data", codec.encode( data )); -- TODO: data size and type etc.

end

--<< Data Handling end >>--




--<< Generic Data Handling >>--

--- Energy Provider implementation

function resources.energy.amount()

    -- TODO: gc_energy_device OR oxygen_collector.getStoredEnergy()

    return resources.energy.attribute_DEFAULT();

end

function resources.energy.max()

    -- TODO: gc_energy_device OR oxygen_collector.getMaxEnergy()

    return resources.energy.attribute_DEFAULT();

end



--- Oxygen Provider implementation

function resources.oxygen.amount()

    local amount = 0;

    for _, collector_data in pairs( oxygen_collectors_data ) do

        amount = amount + collector_data.oxygen_tank.amount;

    end


    return amount;

end

function resources.oxygen.capacity()

    local capacity = 0;

    for _, collector_data in pairs( oxygen_collectors_data ) do

        capacity = capacity + collector_data.oxygen_tank.capacity;

    end


    return capacity;

end

resources.oxygen["in"] = function ()

    local rate = 0;

    for _, collector_data in pairs( oxygen_collectors_data ) do

        rate = rate + collector_data.oxygen_rate;

    end


    return rate;  -- TODO: check and possibly convert to some generic rate (e.g. per tick or per second)

end

--<< Generic Data Handling end >>--




--<< Display Functions >>--

--- Sets up the gui and initialize elements
function display_setup()

    term.clear();

    gui_buffer = gpu.allocateBuffer();
    gpu.setActiveBuffer( gui_buffer );





    --[[ GUI elements init ]]--

        --- Main container holding all gui elements
        gui_elements.container_main = graphics.container(
            x,
            y,
            width,
            height,
            1,
            "OXYGEN COLLECTOR",
            0x0
        );





        --[[ LAUNCH CONTAINER ]]--

            --

        --[[ LAUNCH CONTAINER END ]]--





        --[[ INFO CONTAINER ]]--

            local container_info_width = width / 4;
            local container_info_height = height / 1.5;
            local container_info_x = (width / 1.2  -  container_info_width / 2);
            local container_info_y = height / 10;

            gui_elements.container_info = graphics.container(
                container_info_x,
                container_info_y,
                container_info_width,
                container_info_height,
                1,
                "Information:",

                colors.primary, --- Background
                colors.border, --- Border
                colors.background, --- Border background
                colors.foreground --- Border label
            );


            gui_elements.container_main:child_add( gui_elements.container_info );




            local label_width = container_info_width;
            local label_height = 1;
            local label_x = 1;
            local label_y = container_info_y;
            local label_spread = container_info_height / 7;

            local label_color_background = colors.secondary;



            --[[ ROCKET LABEL ]]--

                gui_elements.label_rocket = graphics.label(
                    label_x,
                    math.floor(label_spread * 1),
                    label_width,
                    label_height,
                    "Rocket: N/A",

                    label_color_background, --- Background
                    colors.foreground --- Label
                );


                gui_elements.container_info:child_add( gui_elements.label_rocket );

            --[[ ROCKET LABEL END ]]--




            --[[ STATUS LABEL ]]--

                gui_elements.label_status = graphics.label(
                    label_x,
                    math.floor(label_spread * 2),
                    label_width,
                    label_height,
                    "Status: N/A",

                    label_color_background, --- Background
                    colors.foreground --- Label
                );


                gui_elements.container_info:child_add( gui_elements.label_status );

            --[[ STATUS LABEL END ]]--




            --[[ OXYGEN PROGRESS BAR ]]--

                local progress_bar_oxygen_height = 5;

                gui_elements.progress_bar_oxygen = graphics.progress_bar(
                    label_x,
                    math.floor(label_spread * 6),
                    label_width,
                    progress_bar_oxygen_height,
                    2,
                    "B",
                    graphics.color_function_default
                );


                gui_elements.container_info:child_add( gui_elements.progress_bar_oxygen );

            --[[ OXYGEN PROGRESS BAR END ]]--

        --[[ INFO CONTAINER END ]]--





        --[[ EVENT LOG ]]--

            local log_events_width = width / 2;
            local log_events_height = height / 4;
            local log_events_x = x;
            local log_events_y = (y + height - log_events_height - 1);
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

    --[[ GUI elements init end ]]--


  


    --- Disable printing to avoid printing straight into gui, but allow the startup/shutdown logs to be printed (see display_stop)
    print_backup = logger.print;
    print_debug_backup = logger.print_debug;
    logger.print = false;
    logger.print_debug = false;



    --- Draw all elements to screen for the very first time and build tree
    gui_elements.container_main:init();


    gpu.bitblt();
    gpu.freeBuffer( gui_buffer );

end

--- Cleans up the gui and prepares for shutdown
function display_stop()

    if gui_elements.container_main then
        gui_elements.container_main:destroy();
    end


    --- Restore old print values to enable shutdown log printing
    logger.print = print_backup;
    logger.print_debug = print_debug_backup;


    gpu.freeAllBuffers();

end

--- Executes data gathering and calls 'display_draw' function
function display_loop()

    --[[ Oxygen Collectors data gathering ]]--

        for i, oxygen_collector in pairs( oxygen_collectors ) do

            oxygen_collectors_data[ oxygen_collector.address ] = {
                oxygen_rate = oxygen_collector.getCollectionSpeed(),
                oxygen_tank = oxygen_collector.getOxygenTank()
            };

        end
        
    --[[ Oxygen Collectors data gathering end ]]--




    display_draw();

end

--- Draws the gui to screen
function display_draw(data)

    event.onError("draw 1")

    local queue_redraw = {};

    gui_buffer = gpu.allocateBuffer();
    gpu.setActiveBuffer( gui_buffer );


    --[[ GUI elements draw ]]--

        --- 'data' should contain only values that should be updated, use full data as backup tho
        data = data or oxygen_collectors_data;




        --[[ EVENT LOG ]]--

            --gui_elements.log_events:redraw();

        --[[ EVENT LOG END ]]--




        --[[ ROCKET LABEL ]]--

            if data.rocket_is_present ~= nil or data.rocket_is_passenger ~= nil then

                gui_elements.label_rocket.text = "Rocket: " .. (
                    data.rocket_is_present
                        and (
                            data.rocket_is_passenger
                                and "Passenger"
                                or "Cargo"
                            )
                        or "N/A"
                    )
                ;
                
                --gui_elements.label_rocket:redraw();
                queue_redraw[ #queue_redraw+1 ] = "label_rocket";

            end


        --[[ ROCKET LABEL END ]]--




        --[[ STATUS LABEL ]]--

            if data.launch_controller_status_update then

                gui_elements.label_status.text = "Status: " .. tostring(launch_controller_status or "N/A");

                --gui_elements.label_status:redraw();
                queue_redraw[ #queue_redraw+1 ] = "label_status";

            end

        --[[ STATUS LABEL END ]]--




        --[[ OXYGEN PROGRESS BAR ]]--

            event.onError("prog bar")

            local oxygen_tank = data[ oxygen_collectors[ 1 ].address ].oxygen_tank or {
                amount = 0.0,
                capacity = 6000.0
            };

            event.onError("prog bar 2")


            gui_elements.progress_bar_oxygen.value_current = oxygen_tank.amount;
            gui_elements.progress_bar_oxygen.value_max = oxygen_tank.capacity;

            event.onError("prog bar 3")

            --gui_elements.progress_bar_oxygen:redraw();
            queue_redraw[ #queue_redraw + 1 ] = "progress_bar_oxygen";

            event.onError("prog bar 4")


        --[[ OXYGEN PROGRESS BAR END ]]--



        --- Collectively redraw elements
        --gui_elements.container_main:redraw();
        for i, element in pairs( queue_redraw ) do

            gui_elements[ element ]:redraw();

        end

    --[[ GUI elements draw end ]]--


    gpu.bitblt();
    gpu.freeBuffer( gui_buffer );

end

--<< Display Functions end >>--









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

    data_send( oxygen_collectors_data );
    
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
            shutdown();
        end

    logger:info("Done.\n");
    --- Check for connection end



    --- Check for oxygen collectors
    logger:info("Checking for oxygen collectors...");

        for address, _ in pairs( component.list("oxygen_collector") ) do

            oxygen_collectors[#oxygen_collectors + 1] = component.proxy( address );

            logger:info("Oxygen collector '" .. tostring( address ) .. "' found.")

        end

        if #oxygen_collectors == 0 then

            logger:error("No oxygen collectors found.");

            -- TODO: shutdown?

        end

    logger:info("Done.\n");
    --- Check for oxygen collectors end

    
    
    --- Configure modem
    logger:info("Configuring modem...");

        modem.open( constants.port.oxygen );
            logger:info("Modem port 'OXYGEN:" .. constants.port.oxygen .. "' opened.\n");

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

        timer_loop = event.timer(1, loop, math.huge);

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



    --- Implement
    logger:info("Implement");

        --

    logger:info("Done.\n");
    --- Implement end



    --- Configure modem
    logger:info("Configuring modem...");

        modem.close( constants.port.oxygen );
            logger:info("Modem port 'OXYGEN:" .. constants.port.oxygen .. "' closed.");

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
    logger:transfer();
    running = false;

    os.exit(0);


    -- TODO: tell common node to disconnect?
end

--<< Main Functions end >>--




startup();

local success, result = thread.waitForAny({thread_interrupt_handler});

shutdown();