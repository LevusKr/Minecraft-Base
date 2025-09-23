--[[
    Launch-Controller
    Launch-Controller component of network cluster structure
    A Launch-Controller acts as manager of multiple launch controllers, thus allowing control of them, e.g. choosing travel destination
    and receiving (and displaying) general information, e.g. current address and destination address
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-launch_controller.log"; -- TODO: create new file at every startup?
local file_launch_controllers = "/etc/launch_controllers.cfg"; --- Database of launch controller name-address pairs
local file_job = "/etc/launch_controller-job.cfg"; --- Configuration file for job mode operation
--


-- Libraries and components
local codec = require("cluster/codec");
local colors = require("cluster/colors-hex");
local Config = require("cluster/config");
local constants = require("cluster/constants");
local graphics = require("cluster/graphics");
local Logger = require("cluster/logger");
local network = require("cluster/network");
local Packet = require("cluster/network_packet");
--local utils_crypt = require("cluster/utils-crypt");

local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local term = require("term");
local thread = require("thread");
local utils = require("cluster/utils");


local modem = component.modem;
local gpu = component.gpu;
local launch_controller = component.launch_controller;
local components = {
    fuel_loader = nil,
    cargo_loader = nil,
    cargo_unloader = nil,
};
--


-- Variables and constants
local logger;
local log_print = true;
local log_debug = true;
local log_verbose = true;
local log_buffer = true;

local hostname = nil;

local timer_loop = 0;
local thread_interrupt_handler = nil;

local refresh_time = 1.25; --- Update interval (refresh rate) [seconds/update]




local launch_controller_register = {}; -- data table storing address-name-pairs ({"Destination_1"=*launch controller address*}, ...)
local launch_controller_register_reverse = {}; -- data table storing name-address-pairs ({*launch controller address*="Destination_1"}, ...)
local launch_controller_register_numbered = {};
local launch_controller_register_count = 0; -- TODO: avoid

local metamethod_add = {__add =
function(old, new)

    for key, new_value in pairs(new) do

        local old_value = old[ key ];

        if old_value ~= new_value then

            old[ key ] = new_value;

        else

            old[ key ] = nil;

        end

    end

    return old;

end
};
local launch_controller_data = setmetatable({}, {}); --- Current data, gathered in display_loop, for usage in display_draw (e.g. destination address, rocket status, ...). Metamethod 
local launch_controller_status = "N/A"; --- Current status. See enum for valid statis
local pending_rocket = {
    target = nil, --- Target or source controller, depending on direction (launching/landing)
    key = nil, --- Identify rocket sequence
    status = nil, --- LANDING or LAUNCHING
}; --- Key of currently pending rocket

local status_launch_controller = {
    FREE = "Free",
    OCCUPIED = "Occupied",
    LAUNCHING = "Launching",
    LANDING = "Landing",
    DISABLED = "Disabled",
    INVALID_LOCAL = "Frequency invalid",
    INVALID_TARGET = "Target invalid",
    UNKNOWN = "N/A",
};

local reasons_launch = {
    SUCCESS = "Launch suceeded",
    FAILURE = "Launch failed",
    FAILURE_DENIED = "Landing permission denied",
    FAILURE_OCCUPIED = "Landing area is occupied",
    FAILURE_IGNITION = "Rocket could not be ignited",
    FAILURE_DESTINATION_INVALID = "Destination address invalid",
}; -- TODO: move enum



-- TODO: implement colored labels
local fuel_loader_status = "N/A";
local cargo_loader_status = "N/A";
local cargo_unloader_status = "N/A";

local status_cargo = {
    SUCCESS = "Working", --- 'SUCCESS' is currently 'Working' because the internal status of the cargo loader/unloader components return 'SUCCESS' when loading items, but we want a clearer status description than 'Success'
    -- WORKING = "Working",
    READY = "Ready",
    DISABLED = "Disabled",
    TARGET_NOT_FOUND = "Target not found",
    TARGET_LACKS_INVENTORY = "Target lacks inventory",
    TARGET_EMPTY = "Target empty",
    TARGET_FULL = "Target full",
    OUT_OF_ITEMS = "Out of items",
    OUT_OF_ENERGY = "Out of energy",
    UNKNOWN = "N/A",
};
--


-- Job system
-- TODO: implement ability to set controller mode to either traffic or job.
--  traffic mode opens communication and landing/launching to the cluster
--  job mode encloses communication with a single peer controller for static rocket control. this will be mostly used as planned cargo rocket controller transferring load from external stations
--    (e.g. transferring asteroid's astro miner's farmed materials to another station/homebase)
local job = {
    config = Config:create( file_job ),
    ready = true, --- False when launchpad components are missing
    available = false, --- True when there is a valid job config
    active = false,
    is_sender = false,
    peer_address = nil
}
--


-- Data tables
local config_launch_controllers = Config:create( file_launch_controllers );
local config_job = Config:create( file_job );
--


-- GUI stuff  TODO: rename
local res_x_backup, res_y_backup = gpu.getResolution();
local res_x, res_y = 160, 50; --- Screen resolution
local x, y = 2, 2; --- Position of drawing container. 1 px allround offset for container's border
local width, height = res_x - 2, res_y - 2; -- Size of drawing container. 1 px allround offset for container's border

local gui_elements = {};

local gui_buffer = nil;
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
local function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if packet_request.port ~= constants.port.space_station then return; end



    local client = packet_request.sender;
    local operation = packet_request.data.operation;
    local payload = packet_request.data.payload;

    logger:info("Client '" .. tostring( client ) .. "' requested '" .. tostring( operation ) .. "' with payload '" .. tostring( payload ) .. "'");



    local response = {
        success = false,
        result = job.active and "Job Active" or "Undefined"
        -- TODO: avoid operation conditionals below to be called if job is indeed active
    };


    if job.active and client == job.peer_address then

        if operation == "dummy" then

            -- TODO: implement possible communication between peers

        end

        
    end


    if operation == "landing_request" then

        if job.active then goto SEND_RESPONSE end

        
        if launch_controller_status == status_launch_controller.DISABLED then

            response.result = "Disabled";
    
        elseif launch_controller_status == status_launch_controller.LAUNCHING then

            response.result = "Launching in progress";

        elseif launch_controller_status == status_launch_controller.LANDING then

            response.result = "Landing in progress";

        else

            response.success = not launch_controller_data.rocket_is_present;
            response.result = response.success and "Granted" or "Occupied";
            response.key = network.generate_packet_id(); --- Use key to identify rocket sequence

            pending_rocket.target = client;
            pending_rocket.key = response.key;

        end


        info("Landing has been requested: " .. tostring( response.result ), response.success and colors.success or colors.failure);

    elseif operation == "launch_confirm" then

        --- 'payload' is a valid sequence key
        if pending_rocket.key == payload then

            --- Set status to LANDING since after launching confirmation there should be a rocket arriving   TODO: timeout if no rocket landed after n seconds and set back to FREE
            launch_controller_status = status_launch_controller.LANDING;
            pending_rocket.status = status_launch_controller.LANDING;

            info(tostring( payload ) .. ": Launch confirmed", colors.success);

        end

    elseif operation == "launch_abort" then

        --- 'payload' is a valid sequence key
        if pending_rocket.key == payload then

            pending_rocket = {};

            info(tostring( payload ) .. ": Launch aborted", colors.warning);

        end

    elseif operation == "landing_confirm" then

        --- 'payload' is a valid sequence key
        if pending_rocket.key == payload then

            pending_rocket = {};

            --- Set status to FREE since until landing confirmation there should be no new rocket yet on launch pad, and if else, automatic rocket detection will handle it
            launch_controller_status = status_launch_controller.FREE;

            info(tostring( payload ) .. ": Landing confirmed", colors.success);

        end

    end


    ::SEND_RESPONSE::




    local send_success, send_result = packet_request:send_response( response );

    if send_success then
        logger:info("Response to client '"  .. tostring( client ) ..  "': '" .. tostring( response.success ) .. " - " .. tostring( response.result ) .. "'\n");
    else
        logger:error("Response to client '"  .. tostring( client ) ..  "' couldn't be sent: " .. tostring( send_result ) .. "\n");
    end

end

--- Sends internal data to Core, passed through by Common Node via internal_data event
function data_send(data)

    event.push("internal_data", data); -- TODO: data size and type etc.

end

--<< Data Handling end >>--




--<< Display Functions >>--

--- Logs to the node logger and display's event log
function info(message, color)

    logger:info( message );
    gui_elements.log_events:log_add(message, color);

end

function warn(message, color)

    logger:warn( message );
    gui_elements.log_events:log_add(message, color or colors.warning);

end

function err(message, color)

    logger:error( message );
    gui_elements.log_events:log_add(message, color or colors.failure);

end


--- Sets up the gui and initialize elements
local function display_setup()

    --- Load launch_controller name-address pairs from file
    local success, result = config_launch_controllers:load();
    
    launch_controller_register = result;

    if not success then

        logger:error("Launch Controller registry could not be loaded: " .. tostring( result ));

        launch_controller_register = {};

    end


    --- Iterate those pairs and...
    for name, address in pairs( launch_controller_register ) do

        -- TODO: REFACTOR, THIS IS SHITTY. maybe nest elements in a numeric indexed table, this makes '_count' and '_numbered' obsolete.
        --          would require __index metatable for querying by name/id instead of index 'i'. this would require the metamethod to loop the whole registry to find at what index any given name/id is.
        --          

        launch_controller_register_count = launch_controller_register_count + 1; --- ...count them
        launch_controller_register_reverse[ tonumber( address ) ] = name; --- ...assign a reverse (address-name) table
        launch_controller_register_numbered[ #launch_controller_register_numbered + 1 ] = tonumber( address ); --- ...assign a numeric (index-address) table

    end

    
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
            "LAUNCH CONTROLLER - " .. tostring(hostname:gsub("launch_controller--", "")),
            0x0
        );





        --[[ LAUNCH CONTAINER ]]--

            local container_launch_width = width / 4;
            local container_launch_height = height / 2;
            local container_launch_x = (width / 2  -  container_launch_width / 2) / 4;
            local container_launch_y = (height / 2  -  container_launch_height / 2) / 3;

            gui_elements.container_launch = graphics.container(
                container_launch_x,
                container_launch_y,
                container_launch_width,
                container_launch_height,
                1,
                "Launch:",

                colors.primary, --- Background
                colors.border, --- Border
                colors.background, --- Border background
                colors.foreground --- Border label
            );


            gui_elements.container_main:child_add( gui_elements.container_launch );




            --[[ DESTINATIONS LIST ]]--

                local list_targets_width = container_launch_width;
                local list_targets_height = launch_controller_register_count;
                local list_targets_x = 1;
                local list_targets_y = 1;

                gui_elements.list_targets = graphics.list(
                    list_targets_x,
                    list_targets_y,
                    list_targets_width,
                    list_targets_height,
                    nil,
                    "Destinations:",

                    colors.secondary, --- Background
                    colors.blue, --- Selected 
                    colors.foreground, --- Label
                    colors.border, --- Border
                    colors.black, --- Border background
                    colors.foreground, --- Border label

                    function(self)

                        local address = launch_controller_register_numbered[ self.index ];

                        launch_controller.setDestinationFrequency( address );


                        gui_elements.log_events:log_add("New destination: " .. launch_controller_register_reverse[ address ]);

                    end
                );


                for name, address in pairs( launch_controller_register ) do

                    gui_elements.list_targets:entry_add(name, address);

                end

                gui_elements.container_launch:child_add( gui_elements.list_targets );

            --[[ DESTINATIONS LIST END ]]--




            --[[ STRIP BUTTON ]]--

                local label_strip_width = 1;
                local label_strip_height = 2;
                local label_strip_x = container_launch_width / 2;
                local label_strip_y = list_targets_height + 1;

                gui_elements.label_strip = graphics.label(
                    label_strip_x,
                    label_strip_y,
                    label_strip_width,
                    label_strip_height,
                    "|\n|",

                    colors.secondary, --- Background
                    colors.foreground --- Label
                );

                gui_elements.container_launch:child_add( gui_elements.label_strip );

            --[[ STRIP BUTTON END ]]--




            --[[ LAUNCH BUTTON ]]--

                local button_launch_width = container_launch_width / 2;
                local button_launch_height = utils.math.odd(3);
                local button_launch_x = (container_launch_width / 2) - (button_launch_width / 2);
                local button_launch_y = list_targets_height + 3;
                local button_launch_label = "LAUNCH";

                gui_elements.button_launch = graphics.button(
                    button_launch_x,
                    button_launch_y,
                    button_launch_width,
                    button_launch_height,
                    button_launch_label,

                    colors.secondary, --- Background
                    colors.loading, --- Selected
                    colors.foreground, --- Label

                    function(self)

                        local success, result = launch(false, false);


                        local color_backup = self.color_selected;
                        self.color_selected = (success and colors.success or colors.failure);

                        self:redraw();

                        event.timer(2.5, function()

                            self.color_selected = color_backup;
                            self.status = false;
                            self:redraw();

                        end, 1); -- TODO: do this in library already

                    end
                );


                gui_elements.container_launch:child_add( gui_elements.button_launch );

            --[[ LAUNCH BUTTON END ]]--

        --[[ LAUNCH CONTAINER END ]]--





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





        --[[ INFO CONTAINER ]]--

            local container_info_width = width / 4;
            local container_info_height = height / 1.75;
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




            --[[ PEER LABEL ]]--
  
                gui_elements.label_job = graphics.label(
                    label_x,
                    math.floor(label_spread * 1.5),
                    label_width,
                    label_height,
                    "Peer mode: " .. tostring(job.active and "Active" or "Inactive"),

                    label_color_background, --- Background
                    job.active and colors.success or colors.foreground --- Label
                );


                gui_elements.container_info:child_add( gui_elements.label_job );

            --[[ PEER LABEL END ]]--




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




            --[[ CARGO STATUS LABEL ]]--
      
                gui_elements.label_status_cargo = graphics.label(
                    label_x,
                    math.floor(label_spread * 3),
                    label_width,
                    label_height + 3,
                    "Cargo Status:\nLoader: N/A\nUnloader: N/A\nFuel: N/A",
                    
                    label_color_background, --- Background
                    colors.foreground, --- Label

                    "CENTER", --- Horizontal alignment
                    "TOP", --- Vertical alignment
                    {
                        popup = true,
                        data = "test"
                    }
                );


                gui_elements.container_info:child_add( gui_elements.label_status_cargo );

            --[[ CARGO STATUS LABEL END ]]--




            --[[ COUNTDOWN LABEL ]]--

                gui_elements.label_countdown = graphics.label(
                    label_x,
                    math.floor(label_spread * 5),
                    label_width,
                    label_height,
                    "Countdown: N/A",
                    
                    label_color_background, --- Background
                    colors.foreground --- Label
                );


                gui_elements.container_info:child_add( gui_elements.label_countdown );

            --[[ COUNTDOWN LABEL END ]]--




            --[[ FUEL PROGRESS BAR ]]--
      
                local progress_bar_fuel_height = 5;

                gui_elements.progress_bar_fuel = graphics.progress_bar(
                    label_x,
                    math.floor(label_spread * 6),
                    label_width,
                    progress_bar_fuel_height,
                    2,
                    "B",
                    graphics.color_function_default
                );


                gui_elements.container_info:child_add( gui_elements.progress_bar_fuel );

            --[[ FUEL PROGRESS BAR END ]]--

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
local function display_stop()

    if gui_elements.container_main then
        gui_elements.container_main:destroy();
    end


    --- Restore old print values to enable shutdown log printing
    logger.print = print_backup;
    logger.print_debug = print_debug_backup;


    gpu.freeBuffer( gui_buffer );

end

--- Executes data gathering and calls 'display_draw' function
local function display_loop()

    --[[ Launch Controller data gathering ]]--

        --- Common address data
        local address_local = tostring( launch_controller.getFrequency() );
        local address_target = tostring( launch_controller.getDestinationFrequency() );


        --- Rocket specific stuff
        local rocket_is_present = launch_controller.isRocketPresent();
        local rocket_countdown = launch_controller.getCountdown();


        

        local merged = {};

        local launch_controller_data_new = setmetatable({
            --- Common address data
            address_local = address_local,
            name_local = launch_controller_register_reverse[ tonumber( address_local ) ],
            status_local = launch_controller.isFrequencyValid(),

            address_target = address_target,
            name_target = launch_controller_register_reverse[ tonumber( address_target ) ],
            status_target = launch_controller.isDestinationFrequencyValid(),


            --- Rocket specific stuff
            rocket_is_present = rocket_is_present,
            rocket_is_starting = launch_controller.isRocketIgnited(),
            rocket_is_passenger = launch_controller.isRocketPassenger(),
            rocket_fuel_tank = launch_controller.getRocketFuelTank(),
            rocket_countdown = rocket_countdown
        }, metamethod_add);
        
        local launch_controller_data_old = launch_controller_data;

        launch_controller_data = launch_controller_data_new;



        -- local function t_merge(old, new)

        --     for key, new_value in pairs(new) do

        --         local old_value = old[ key ];

        --         if old_value ~= new_value then
        
        --             old[ key ] = new_value;
        
        --         else

        --             old[ key ] = nil;

        --         end

        --     end

        --     return old;
            
        -- end

        --- Simply add old and new tables to overwrite updated fields (see declaration of 'launch_controller_data'). This is handed to 'display_draw'
        merged = launch_controller_data_old + launch_controller_data_new;
        -- merged = t_merge(launch_controller_data_old, launch_controller_data_new);



        local launch_controller_status_old = launch_controller_status; --- Save for later recognizing if updated

        --- Update status according to current conditions
        if not launch_controller.isEnabled() then
            
            launch_controller_status = status_launch_controller.DISABLED;
            gui_elements.label_status.color_background = colors.gray;
            
        elseif launch_controller_data.status_local == false then

            --- Local frequency is invalid
            launch_controller_status = status_launch_controller.INVALID_LOCAL;
            gui_elements.label_status.color_background = colors.red;
    
        elseif launch_controller_data.status_target == false then

            --- Target frequency is invalid
            launch_controller_status = status_launch_controller.INVALID_TARGET;
            gui_elements.label_status.color_background = colors.red;
    
        elseif rocket_is_present == true and rocket_countdown >= 1.0 then

            --- If a previously approved rocket landed send landing confirmation to source
            if launch_controller_status == status_launch_controller.LANDING then

                --- Confirms currently pending landing
                landing_confirm();

                logger:info(pending_rocket.key .. ": Landing completed");
                gui_elements.log_events:log_add(pending_rocket.key .. ": Landing completed", colors.success);

                pending_rocket = {};

                -- TODO: somehow differ between rocket which requested landing clearance and others so a warning
                --       can be issued to remove faulty rocket because approved rocket is about to land (boom) (avoid players (me (the only one playing this world (  :/  )))) to get near)

            end

            if launch_controller_status ~= status_launch_controller.OCCUPIED then

                gui_elements.log_events:log_add("Rocket detected.");

                launch_controller_status = status_launch_controller.OCCUPIED;
                gui_elements.label_status.color_background = colors.secondary;

            end

        --- "Launching" and "Landing" are ignored when no other rocket is present because they only get updated by landing confirmation or when rocket is present (see above)
        elseif launch_controller_status ~= status_launch_controller.LAUNCHING and launch_controller_status ~= status_launch_controller.LANDING then

            if launch_controller_status ~= status_launch_controller.FREE then

                gui_elements.log_events:log_add("No rocket detected.");

                launch_controller_status = status_launch_controller.FREE;

            end

        end

        --- Avoid the status and process of launching/landing getting interrupted by e.g. the controller getting disabled and thus avoiding sending landing confirmation
        if pending_rocket.status then
            
            launch_controller_status = pending_rocket.status;

        end
        

        local launch_controller_status_update = launch_controller_status_old == launch_controller_status;
        
    --[[ Launch Controller data gathering end ]]--




    
    --[[ Cargo Controllers data gathering ]]--

        local fuel_loader_status_old = fuel_loader_status;

        --- Update Fuel Loader's status
        if not fuel_loader.isEnabled() then

            fuel_loader_status = status_cargo.DISABLED;

        elseif fuel_loader.isLoading() then

            fuel_loader_status = status_cargo.SUCCESS;

        elseif fuel_loader.getStoredEnergy() < 50 then -- TODO: hardcoded and kind of random at 50 instead of 0 due to possible flickering between no energy and just enough

            fuel_loader_status = status_cargo.OUT_OF_ENERGY;

        else

            fuel_loader_status = status_cargo.READY;

        end

        local fuel_loader_status_update = fuel_loader_status_old == fuel_loader_status;
    

        local _, status_loader = cargo_loader.getStatus();
        local cargo_loader_status_old = cargo_loader_status;

        --- Update Cargo Loader's status
        if not cargo_loader.isEnabled() then

            cargo_loader_status = status_cargo.DISABLED;

        elseif cargo_loader.getStoredEnergy() < 50 then -- TODO: hardcoded and kind of random at 50 instead of 0 due to possible flickering between no energy and just enough

            cargo_loader_status = status_cargo.OUT_OF_ENERGY;

        else

            cargo_loader_status = status_cargo[ status_loader ];

        end

        local cargo_loader_status_update = cargo_loader_status_old == cargo_loader_status;


        local _, status_unloader = cargo_unloader.getStatus();
        local cargo_unloader_status_old = cargo_unloader_status;

        --- Update Cargo Unloader's status
        if not cargo_unloader.isEnabled() then

            cargo_unloader_status = status_cargo.DISABLED;

        elseif cargo_unloader.getStoredEnergy() < 50 then -- TODO: hardcoded and kind of random at 50 instead of 0 due to possible flickering between no energy and just enough

            cargo_unloader_status = status_cargo.OUT_OF_ENERGY;

        else

            cargo_unloader_status = status_cargo[ status_unloader ];

        end

        local cargo_unloader_status_update = cargo_unloader_status_old == cargo_unloader_status;

    --[[ Cargo Controllers data gathering end ]]--




    local updates = {};
    updates.launch_controller_status_update = launch_controller_status_update;
    updates.fuel_loader_status_update = fuel_loader_status_update;
    updates.cargo_loader_status_update = cargo_loader_status_update;
    updates.cargo_unloader_status_update = cargo_unloader_status_update;

    display_draw( merged, updates );

end

--- Draws the gui to screen
function display_draw(data, updates)

    -- event.onError(tostring(computer.uptime()))

    local queue_redraw = {};
    
    gui_buffer = gpu.allocateBuffer();
    gpu.setActiveBuffer( gui_buffer );


    --[[ GUI elements draw ]]--

        --- 'data' should contain only values that should be updated, use full data as backup tho
        data = data or launch_controller_data;




        --[[ EVENT LOG ]]--

            --gui_elements.log_events:redraw();
            queue_redraw[ #queue_redraw+1 ] = "log_events"

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

            if updates.launch_controller_status_update then

                gui_elements.label_status.text = "Status: " .. tostring(launch_controller_status or "N/A");

                --gui_elements.label_status:redraw();
                queue_redraw[ #queue_redraw+1 ] = "label_status";

            end

        --[[ STATUS LABEL END ]]--




        --[[ STATUS LABEL ]]--

            if updates.cargo_loader_status_update or updates.cargo_unloader_status_update then

                gui_elements.label_status_cargo.text =
                    "Cargo Status:\nFuel: ".. tostring(fuel_loader_status or "N/A") ..
                    "\nUnloader: " .. tostring(cargo_unloader_status or "N/A") ..
                    "\nLoader: ".. tostring(cargo_loader_status or "N/A");

                --gui_elements.label_status_cargo:redraw();
                queue_redraw[ #queue_redraw+1 ] = "label_status_cargo";

            end

        --[[ STATUS LABEL END ]]--




        --[[ COUNTDOWN LABEL ]]--

            local rocket_countdown = data.rocket_countdown;

            if rocket_countdown then

                gui_elements.label_countdown.text = "Countdown: " .. tostring(rocket_countdown or "N/A");

                --gui_elements.label_countdown:redraw();
                queue_redraw[ #queue_redraw+1 ] = "label_countdown";

            end

        --[[ COUNTDOWN LABEL END ]]--




        --[[ FUEL PROGRESS BAR ]]--

            local fuel_tank = data.rocket_fuel_tank or {
                amount = 0.0,
                capacity = 2000.0
            };


            if fuel_tank then

                gui_elements.progress_bar_fuel.value_current = fuel_tank.amount;
                gui_elements.progress_bar_fuel.value_max = fuel_tank.capacity;

                --gui_elements.progress_bar_fuel:redraw();
                queue_redraw[ #queue_redraw+1 ] = "progress_bar_fuel";

            end

        --[[ FUEL PROGRESS BAR END ]]--



        --- Collectively redraw elements
        gui_elements.container_main:redraw();
        queue_redraw[ #queue_redraw+1 ] = "container_launch"
        -- for i, element in pairs( queue_redraw ) do

        --     gui_elements[ element ]:redraw();

        -- end

    --[[ GUI elements draw end ]]--


    gpu.bitblt();
    gpu.freeBuffer( gui_buffer );

end

--<< Display Functions end >>--




--<< Node Functions >>--

--- Launch rocket from launch pad and notify destination's launch controller
function launch(skip_fuel_check, skip_destination_check)

    -- TODO: refactor. currently, due to performance issues, the job mode loop tries to start the rocket more than once since the loop runs again before all stati are set accordingly and the rocket actually launched
    if pending_rocket.key then

        logger:error("Launching failed: Pending rocket sequence");
        gui_elements.log_events:log_add("Launch failed: Pending rocket sequence", colors.failure);

        return false, "Pending rocket sequence";

    end


    local success_request, result_request, key_request, target = false, "Landing permission denied", nil, nil;

    --- Request landing permission on destination controller
    if not skip_destination_check then

        logger:info("Requesting landing permission from '" .. launch_controller_data.name_target .. "'...");
        gui_elements.log_events:log_add("Requesting landing permission from '" .. launch_controller_data.name_target .. "'...", colors.loading);

        --- Whether permission granted or not and additional information/error message
        success_request, result_request, key_request, target = launch_request();

        logger:info("Requested landing permission: " .. tostring( result_request ));
        gui_elements.log_events:log_add("Landing permission request: " .. tostring( result_request ), success_request and colors.success or colors.failure);


        pending_rocket = {
            target = target,
            key = key_request
        };
        
    else

        logger:warn("Skipping destination check");
        gui_elements.log_events:log_add("Skipping destination check", colors.warning);

        -- TODO: currently, pending_rocket will be empty under these conditions since we didn't receive a sequence key from the destination due to skipping the check

    end


    local success_launch, result_launch = false, "Failure";
    local log_message, log_color = "Failure", colors.foreground;

    --- If landing permission is granted, try to launch and await internal lauch success along with optional error message
    if success_request or skip_destination_check then

        success_launch, result_launch = launch_controller.launch( skip_fuel_check );

        --- If launching succeeded internally (Galacticraft-sided)
        if success_launch then

            logger:info(pending_rocket.key .. ": Launching succeeded: " .. tostring( result_launch ));
      
            log_message = pending_rocket.key .. ": Launching";
            log_color = colors.success;


            --- Confirms currently pending launch
            launch_confirm();


            launch_controller_status = status_launch_controller.LAUNCHING;
            -- launch_controller_status_color = colors.loading;
            gui_elements.label_status.color_background = colors.loading;
            gui_elements.label_status:redraw(); -- TODO: check if auto redraw is fully implemented yet and if, remove this

        else

            logger:error(pending_rocket.key .. ": Launching failed internally: " .. tostring( result_launch ));

            log_message = pending_rocket.key .. ": Launch failed: " .. tostring( result_launch );
            log_color = colors.failure;


            --- Aborts currently pending launch
            launch_abort();


            pending_rocket = {};

        end

    else

        logger:error(pending_rocket.key .. ": Launching failed: " .. tostring( result_request ));

        log_message = pending_rocket.key .. ": Launch failed: " .. tostring( result_request );
        log_color = colors.failure;


        pending_rocket = {};

    end



    --[[ TODO: currently we are waiting for a full landing confirmation before clearing launch pad for other rockets (i.e. setting status to FREE). theoretically we can calculate how much time we need to wait
                by rocket type, countdown and gravitation until rocket is gone into space and collision with other landing rockets is impossible (at least unlikely under normal conditions)

    --- After 10 seconds assert that rocket launched and landing pad is free and change status again. This avoids launching and possbile other landing rockets from colliding mid-air
    event.timer(
        10,
        function()

            --- If status was still 'LAUNCHING', set to 'FREE'. Manually placing a new rocket would have changed the status to 'OCCUPIED', so don't do falsey concurrent modification
            if launch_controller_status == status_launch_controller.LAUNCHING then
                
                launch_controller_status = status_launch_controller.FREE;

            end

        end,
        1
    );
    --]]


    --- Add log in appropriate color to event log
    gui_elements.log_events:log_add(log_message, log_color);
  
  
    --- Broadcast success of launch along with information like name and destination
    -- TODO: implement, but not as broadcast. more like one administrative node checking space traffic and detecting obscure behaviour yknow



    return success_launch, result_launch;
    
end

--- Requests landing permission from given target (actual cluster hostname with prefix 'launch_controller-')
function launch_request(target)

    target = target or ("launch_controller-" .. launch_controller_data.name_target);


    local packet_request = Packet:create(
        modem.address,
        target,
        constants.port.space_station,
        constants.packet.data,
        {
            operation = "landing_request",
            payload = hostname
        }
    );

    packet_request:send();

    

    local success = false;
    local result = 'Destination controller unreachable';
    local key = nil;

        
    local success_response, result_response = packet_request:await_response();

    if success_response then

        success = result_response.data.success;
        result = result_response.data.result;
        key = result_response.data.key;

    else

        success = false;
        result = result_response or result;

    end


    return success, result, key, target;

end

--- Confirms launch to target for previously granted and thus pending sequence
function launch_confirm(pending)

    return TODO_think_of_name("launch_confirm", pending);

end

--- Aborts launch to target for previously granted and thus pending sequence
function launch_abort(pending)

    return TODO_think_of_name("launch_abort", pending);

end


--- Confirms landing for previously granted and thus pending sequence
function landing_confirm(pending)

    return TODO_think_of_name("landing_confirm", pending);

end


function TODO_think_of_name(operation, pending)

    pending = pending or pending_rocket;

    if not pending then return end


    local packet_request = Packet:create(
        modem.address,
        pending.target,
        constants.port.space_station,
        constants.packet.data,
        {
            operation = operation,
            payload = pending.key
        }
    );

    return packet_request:send(), packet_request;

end



local function job_loop()

    if job.active then

        --- Whether this Controller is the sender of cargo, thus wait for loading to be completed...
        if job.is_sender and cargo_loader_status == status_cargo.TARGET_FULL then

            pending_rocket.target = job.peer_address;
            pending_rocket.status = status_launch_controller.LAUNCHING;

            launch();

        --- ... or vice versa.
        elseif not job.is_sender and cargo_unloader_status == status_cargo.TARGET_EMPTY then

            -- Rakete ist entladen -> Rückflug vorbereiten (Landeerlaubnis wird in launch() angefragt)

            pending_rocket.target = job.peer_address;
            pending_rocket.status = status_launch_controller.LAUNCHING;

            launch();

        end

    end

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
local function loop()

    display_loop();

    --data_send(launch_controller_data);

    job_loop();

end

--- Main startup function, executed once at startup
local function startup()

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



    --- Check for available components
    logger:info("Configuring launchpad components...");

        local available_components = {
            { name = "fuel_loader", canonicalName = "Fuel Loader" },
            { name = "cargo_loader", canonicalName = "Cargo Loader" },
            { name = "cargo_unloader", canonicalName = "Cargo Unloader" }
        };
        
        for _, available_component in pairs( available_components ) do

            local name = available_component.name;
            local canonical_name = available_component.canonicalName;
            local is_available = component.isAvailable( name );
        
            if is_available then

                _ENV[ name ] = component[ name ];
                logger:info(canonical_name .. " connected.");

            else

                job.ready = false;
                logger:warn("No " .. canonical_name .. " found.");

            end

        end

    logger:info("Done.\n");
    --- Check for available components end



    --- Check for available job
    logger:info("Checking for available job...");

        local success, result = config_job:load();


        job.is_sender = result.is_sender or job.is_sender; --- Keep original default value
        job.peer_address = result.peer_address or job.peer_address; --- Keep possibilty of implementing default value in job table

        if (not success) or job.peer_address == nil then

            logger:info("No job available: " .. tostring( result ));

        else

            job.active = true;

            logger:info("Job mode active. Peer: " .. tostring( job.peer_address ));

        end

    logger:info("Done.\n");
    --- Check for available components end

    
    
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
            logger:info("Screen Resolution set to '" .. res_x .. "x" .. res_y .. "'.");

        gpu.freeAllBuffers();
            logger:info("Free'd all VRAM buffers.");

        display_setup();

    logger:info("Done.\n ");
    --- Setup GUI end



    local time_startup_finished = computer.uptime() - time_startup;
    logger:info("Successfully started up in " .. time_startup_finished .. " seconds.\n\n");
end

--- Main shutdown function, executed once at shutdown
local function shutdown()

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

        event.cancel( timer_loop );

    logger:info("Done.\n");
    --- Stop loop end
    

    
    --- Stop GUI
    logger:info("Stopping GUI...");

        gpu.setResolution(res_x_backup, res_y_backup);
            logger:info("Screen Resolution set to '" .. res_x_backup .. "x" .. res_y_backup .. "'");

        -- TODO: should this be called earlier? logs are just being printed from here on, so most of the shutdown log is not visible, does that matter?
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
-- event.onError("----cluster-node-launch_controller.lua----");
-- event.onError(success);
-- event.onError(result);
-- event.onError("----cluster-node-launch_controller.lua----");

shutdown();