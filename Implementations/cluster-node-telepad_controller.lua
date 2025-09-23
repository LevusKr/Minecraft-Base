--[[
    Telepad-Controller
    Telepad-Controller component of network cluster structure
    A Telepad-Controller acts as manager of a single telepad, thus allowing control of it, e.g. choosing travel destination
    and receiving (and displaying) general information, e.g. current address and destination address
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-telepad_controller.log"; -- TODO: create new file at every startup?
local file_telepad_controller = "/etc/telepad_register.cfg";
--

-- Libraries and components
local colors = require("cluster/colors-hex");
local Config = require("cluster/config");
local constants = require("cluster/constants");
local graphics = require("cluster/graphics");
local Logger = require("cluster/logger");
local Packet = require("cluster/network_packet");

local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local term = require("term");
local thread = require("thread");
local utils = require("cluster/utils");


local modem = component.modem;
local gpu = component.gpu;
local telepad = component.telepad;
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


local telepad_register_count = 0; -- TODO: avoid
local telepad_register = setmetatable({}, {__len = function() return telepad_register_count end}); -- data table storing address-name-pairs ({"Destination_1"=*launch controller address*}, ...)
local telepad_register_reverse = setmetatable({}, {__len = function() return telepad_register_count end}); -- data table storing name-address-pairs ({*launch controller address*="Destination_1"}, ...)
local telepad_register_numbered = {};

local telepad_controller_data = {}; --- Current data, gathered in display_loop, for usage in display_draw (e.g. destination address, rocket status, ...)
local telepad_controller_status = "N/A"; --- Current status. See enum for valid statis

local status_telepad_controller = {
    READY = "Ready",

    DISABLED = "Disabled",
    INVALID_LOCAL = "Frequency invalid",
    INVALID_TARGET = "Target invalid",
    UNKNOWN = "N/A",
};
--

-- Data tables
local config_telepad_register = Config:create( file_telepad_controller );
--

-- GUI stuff  TODO: rename
local res_x_backup, res_y_backup = gpu.getResolution();
local res_x, res_y = 96, 30; --- Screen resolution
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


    if operation == "data" then


        response.success = true;

        gui_elements.log_events:log_add("Data request.");


        if payload == "status" then

            response.result = telepad_controller_status;

        elseif payload == "state" then

            response.result = telepad.isEnabled();

        elseif telepad_controller_data[ payload ] then

            --- Request arbitrary data parameter
            response.result = telepad_controller_data[ payload ];

        else

            response.result = telepad_controller_data;

        end


        gui_elements.log_events:log_add("Response: " .. tostring( response.success ) .. " : " .. tostring( response.result ));


    elseif operation == "enable" then


        local state, state_old = toggle( true );

        response.success = true;
        response.result = (state == state_old) and "Already enabled" or "Enabled";


    elseif operation == "disable" then


        local state, state_old = toggle( false );

        response.success = true;
        response.result = (state == state_old) and "Already disabled" or "Disabled";


    elseif operation == "toggle" then


        local state = toggle( tonumber( payload ) );

        response.success = true;
        response.result = state and "Enabled" or "Disabled";


    elseif operation == "set_target" then


        telepad.setTargetAddress( payload );
    

        gui_elements.log_events:log_add("Remote target set.");
        gui_elements.log_events:log_add("New target: " .. telepad_register_reverse[ payload ]);

        response.success = true;
        response.result = "Target changed";

        
    end

  

    Packet:create(
        modem.address,
        client,
        packet_request.port,
        constants.packet.response,
        response
    ):send();
  
    logger:info("Response to client '"  .. tostring( client ) ..  "': '" .. tostring( response.success ) .. " - " .. tostring( response.result ) .. "'\n");

end

--- Sends internal data to Core, passed through by Common Node via internal_data event
function data_send(data)
    
    event.push("internal_data", data); -- TODO: data size and type etc.
    
end

--<< Data Handling end >>--




--<< Display Functions >>--

--- Sets up the gui and initialize elements
function display_setup()

    --- Load telepad name-address pairs from file
    local success, result = config_telepad_register:load();
    
    telepad_register = result;

    if not success then

        logger:error("Telepad registry could not be loaded: " .. tostring( result ));

        telepad_register = {};

    end


    --- Iterate those pairs and...
    for name, address in pairs( telepad_register ) do

        telepad_register_count = telepad_register_count + 1; --- ...count them
        telepad_register_reverse[ tonumber( address ) ] = name; --- ...assign a reverse (address-name) table
        telepad_register_numbered[ #telepad_register_numbered + 1 ] = tonumber( address ); --- ...assign a numeric (index-address) table

    end

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
            1,
            1,
            res_x,
            1,
            "TELEPAD CONTROLLER DISPLAY",
            colors.primary, --- Background
            colors.foreground --- Label
        );

        gui_elements.container_main:child_add( gui_elements.label_title );





        --[[ DESTINATIONS LIST ]]--

            local list_targets_width = res_x / 3;
            local list_targets_height = telepad_register_count + 1;
            local list_targets_x = (res_x / 2  -  list_targets_width / 2) / 3;
            local list_targets_y = (res_y / 2  -  list_targets_height / 3);

            gui_elements.list_targets = graphics.list(
                list_targets_x,
                list_targets_y,
                list_targets_width,
                list_targets_height,
                1,
                "Destinations:",

                colors.primary, --- Background
                colors.blue, --- Selected 
                colors.foreground, --- Label
                colors.border, --- Border
                colors.black, --- Border background
                colors.foreground, --- Border label
                
                function(self)

                    local address = telepad_register_numbered[ self.index ];
    
                    telepad.setTargetAddress( address );
    
    
                    gui_elements.log_events:log_add("New destination: " .. telepad_register_reverse[ address ]);
                    
                end
            );


            for name, address in pairs( telepad_register ) do
                gui_elements.list_targets:entry_add(name, address);
            end

            gui_elements.container_main:child_add(gui_elements.list_targets);
  
        --[[ DESTINATIONS LIST END ]]--





        --[[ EVENT LOG ]]--

            local log_events_width = res_x / 2;
            local log_events_height = res_y / 5;
            local log_events_x = x;
            local log_events_y = (y + res_y - log_events_height);
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





        --[[ INFO CONTAINER ]]--

            local container_info_width = res_x / 3;
            local container_info_height = res_y / 4;
            local container_info_x = (res_x / (4 / 3)  -  container_info_width / 2);
            local container_info_y = res_y / 7;

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




            local label_width = gui_elements.container_info.width;
            local label_height = 1;
            local label_x = 1;
            local label_y = gui_elements.container_info.height;
            local label_spread = 5;

            local label_color_background = colors.secondary;




            --[[ STATUS LABEL ]]--
      
                gui_elements.label_status = graphics.label(
                    label_x,
                    label_y / (label_spread / 2),
                    label_width,
                    label_height,
                    "Status: UNKNOWN",
                    
                    label_color_background, --- Background
                    colors.foreground --- Label
                );


                gui_elements.container_info:child_add( gui_elements.label_status );

            --[[ STATUS LABEL END ]]--




            --[[ TARGET STATUS LABEL ]]--
      
                gui_elements.label_status_target = graphics.label(
                    label_x,
                    label_y / (label_spread / 3),
                    label_width,
                    label_height,
                    "Target Status: UNKNOWN",
                
                    label_color_background, --- Background
                    colors.foreground --- Label
                );


                gui_elements.container_info:child_add( gui_elements.label_status_target );

            --[[ TARGET STATUS LABEL END ]]--

        --[[ INFO CONTAINER END ]]--

    --[[ GUI elements init end ]]--


  


    --- Disable printing to avoid printing straight into gui, but allow the startup/shutdown logs to be printed (see display_stop)
    print_backup = logger.print;
    print_debug_backup = logger.print_debug;
    logger.print = false;
    logger.print_debug = false;



    --- Draw all elements to screen for the very first time and build tree
    gui_elements.container_main:init();

end

--- Cleans up the gui and prepares for shutdown
function display_stop()

    if gui_elements.container_main then
        gui_elements.container_main:destroy();
    end


    --- Restore old print values to enable shutdown log printing
    logger.print = print_backup;
    logger.print_debug = print_debug_backup;

end

--- Draws the gui to screen
function display_draw()

    --[[ GUI elements draw ]]--

        --[[ EVENT LOG ]]--

            gui_elements.log_events:redraw();

        --[[ EVENT LOG END ]]--




        --[[ STATUS LABEL ]]--

            gui_elements.label_status.text = "Status: " .. tostring(telepad_controller_status or "UNKNOWN");

            gui_elements.label_status:redraw();

        --[[ STATUS LABEL END ]]--




        --[[ TARGET STATUS LABEL ]]--

            gui_elements.label_status_target.color_background = telepad_controller_data.status_target[1] and colors.green or colors.red;
            gui_elements.label_status_target.text = "Target Status: " .. tostring(telepad_controller_data.status_target[2] or "UNKNOWN");

            gui_elements.label_status_target:redraw();

        --[[ TARGET STATUS LABEL END ]]--

    --[[ GUI elements draw end ]]--

end

--- Executes data gathering and calls 'display_draw' function
function display_loop()

    --[[ Telepad Controller data gathering ]]--

        --- Common address data
        local address_local = tostring( telepad.getAddress() );
        local name_local = telepad_register_reverse[ tonumber( address_local ) ];
        local status_local = telepad.isAddressValid();

        local address_target = tostring( telepad.getTargetAddress() );
        local name_target = telepad_register_reverse[ tonumber( address_target ) ];
        local status_target = { telepad.getTargetStatus() };


        telepad_controller_data = {
            address_local = address_local,
            name_local = name_local,
            status_local = status_local,

            address_target = address_target,
            name_target = name_target,
            status_target = status_target
        };
        

        if not telepad.isEnabled() then

            telepad_controller_status = status_telepad_controller.DISABLED;

        elseif not telepad_controller_data.status_local then

            --- Local frequency is invalid
            telepad_controller_status = status_telepad_controller.INVALID_LOCAL;
    
        elseif not telepad_controller_data.status_target[1] then

            --- Target frequency is invalid
            telepad_controller_status = status_telepad_controller.INVALID_TARGET;
    
        else

            telepad_controller_status = status_telepad_controller.READY;

        end
        
    --[[ Telepad data gathering end ]]--




    display_draw();

end

--<< Display Functions end >>--




--<< Node Functions >>--

--- Either toggle status or set to 'status_new'
function toggle(state_new)

    local state_current = telepad.isEnabled();
    local state = state_new or (not state_current);
    telepad.setEnabled( state );

    gui_elements.log_events:log_add("Toggled power mode. " .. (state and "Enabled" or "Disabled"));


    return state, state_current;

end

function check_destination()

    local packet_request = Packet:create(
        modem.address,
        "telepad_controller-" .. telepad_controller_data.name_target,
        constants.port.main,
        constants.packet.data,
        {
            operation = "request_teleport",
            payload = hostname
        }
    );

    packet_request:send(true);

    
    local success = false;
    local result = "Destination controller unreachable";

        
    local response_future = packet_request:await_response();

    response_future:on_success(
        function(packet_response)
    
            success = packet_response.data.success;
            result = packet_response.data.result;
    
        end
    ):on_failure(
        function(message)
    
            success = false;
            result = message or result;
    
        end
    ):on_completion(
        function()
    
            response_future.result = {
                success = success,
                result = result
            }
    
        end
    );


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

--- Main loop function, executed once every second
function loop()

    display_loop();

    --data_send( telepad_controller_data );

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

        modem.close( constants.port.main );
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

local success, result = thread.waitForAny({thread_interrupt_handler});

shutdown();