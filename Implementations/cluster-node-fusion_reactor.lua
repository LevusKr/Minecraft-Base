--[[
    Fusion Reactor
    Fusion Reactor component of network cluster structure
    A Fusion Reactor acts as graphical interface of a Mekanism Fusion Reactor, thus computing and displaying
    important and interesting information, e.g. current energy level, production rate etc.
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-fusion_reactor.log";
--

-- Libraries and components
local codec = require("cluster/codec");
local colors = require("cluster/colors-hex");
local constants = require("cluster/constants");
local graphics = require("cluster/graphics");
local Logger = require("cluster/logger");
local Packet = require("cluster/network_packet");
local energy_provider = require("/etc/rc.d/cluster-energy_provider");

local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local term = require("term");
local thread = require("thread");
local utils = require("cluster/utils");


local modem = component.modem;
local gpu = component.gpu;
local matrix = component.fusion_reactor or component.fusionsreaktor;
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


local matrix_ready = type( matrix.getEnergy() ) == "number"; --- If Matrix is not ready (multi block structure incomplete), this will be NaN

local unit_energy = "RF"; --- Energy unit (Redstone Flux)
local unit_factor = 0.4; --- Energy unit conversion factor (Mekanism Joules to Redstone Flux)
local refresh_time = 0.5; --- Update interval (refresh rate) [seconds/update]
--

-- Data tables
local values_in = {}; --- Current to-be-displayed input values
local values_out = {}; --- Current to-be-displayed output values
--

-- GUI stuff  TODO: rename
local res_x_backup, res_y_backup = gpu.getResolution();
local res_x, res_y = 160, 50; --- Screen resolution
local x, y = 1, 1; --- Position of drawing container
local width, height = res_x, res_y; --- Size of drawing container (here: fullscreen)
local color_out, color_in, color_background = colors.red, colors.green, 0x5A5A5A; --- Graphs and background colors


local values_io_count = math.ceil( width / 2 - 2); --- Count of I/O values displayed
local values_io_count_buffer = 5
local value_io_max =
    matrix_ready
    and (matrix.getTransferCap() * unit_factor)
    or 0
; --- Maximum of I/O values (max transfer rate)


local value_energy_max =
    matrix_ready
    and (matrix.getMaxEnergy() * unit_factor)
    or 0
; --- Maximum of energy values (max storage cap)

local value_energy =
    matrix_ready
    and (matrix.getEnergy() * unit_factor)
    or 0
; --- Current energy value


local label_energy_prognosis = {
    label = "STATUS N/A",
    color = colors.red
}; --- Label for prognosis of energy storage


local gui_elements = {};
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if packet_request.port ~= constants.port.energy then return; end



    local client = packet_request.sender;
    local operation = packet_request.data.operation;
    local payload = packet_request.data.payload;

    logger:info("Client '" .. tostring( client ) .. "' requested '" .. tostring( operation ) .. "' with payload '" .. tostring( payload ) .. "'");



    local response = {
        success = false,
        result = "Undefined"
    };


    if operation == "toggle" then

        --- Toggle I/O of matrix   TODO: realistic to achieve through redstone?
        if payload == "in" then

            -- TODO: toggle input of energy

        elseif payload == "out" then

            -- TODO: toggle output of energy

        end

    end



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

--- Energy Provider implementation   TODO: respect matrix_ready

function energy_provider.energy_current()

    return matrix_ready and matrix.getEnergy() or nil;

end

function energy_provider.energy_max()

    return matrix.getMaxEnergy();

end

function energy_provider.energy_in()

    return matrix.getInput();

end

function energy_provider.energy_out()

    return matrix.getOutput();

end

function energy_provider.energy_transfer()

    return matrix.getInput() - matrix.getOutput();

end

function energy_provider.energy_transfer_max()

    return matrix.getTransferCap();

end


--- XXX implementation

--<< Generic Data Handling end >>--




--<< Display Functions >>--

--- Sets up the gui and initialize elements
function display_setup()
    
    if matrix_ready then

        for i = 1, values_io_count + values_io_count_buffer do

            table.insert(values_out, 1, matrix.getOutput() * unit_factor);
            table.insert(values_in, 1, matrix.getInput() * unit_factor);
    
        end

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
            colors.black
        );




        --- Program Title
        gui_elements.label_title = graphics.label(
            1,
            1,
            res_x,
            1,

            "INDUCTION MATRIX DISPLAY",

            colors.primary, --- Background
            colors.foreground --- Label
        );

        gui_elements.container_main:child_add( gui_elements.label_title );





        --[[ ENERGY I/O HISTOGRAMS ]]--

            local histogram_energy_io_width = values_io_count;
            local histogram_energy_io_height = res_y / 2 - 2;
            local histogram_energy_io_y = y + 2;
            local histogram_energy_io_y_max = histogram_energy_io_y + histogram_energy_io_height - 1;

            local histogram_energy_in_x = x + 1;
            local histogram_energy_out_x = res_x / 2 + 2; --- +1 for edge offset (see line above)  AND  +1 for gap between graphs

            local histogram_energy_io_labels = true;


            gui_elements.histogram_energy_in = graphics.histogram_vertical(
                histogram_energy_in_x,
                histogram_energy_io_y,
                histogram_energy_io_width,
                histogram_energy_io_height,
        
                value_io_max,
                unit_energy,
                values_io_count,

                color_background,
                color_in,
                0xFFFFFF,

                histogram_energy_io_labels
            );

            gui_elements.container_main:child_add( gui_elements.histogram_energy_in );


            gui_elements.histogram_energy_out = graphics.histogram_vertical(
                histogram_energy_out_x,
                histogram_energy_io_y,
                histogram_energy_io_width,
                histogram_energy_io_height,
        
                value_io_max,
                unit_energy,
                values_io_count,

                color_background,
                color_out,
                0xFFFFFF,

                histogram_energy_io_labels
            );

            gui_elements.container_main:child_add( gui_elements.histogram_energy_out );

        --[[ ENERGY I/O HISTOGRAMS END ]]--
        
        
        
        
        --[[ ENERGY PROGRESS BAR ]]--

            local progress_bar_energy_width = res_x - 4;
            local progress_bar_energy_height = (res_y / 2.5) - 4;
            local progress_bar_energy_x = x + 2;
            local progress_bar_energy_y = y + (res_y - progress_bar_energy_height) - 1;

            gui_elements.progress_bar_energy = graphics.progress_bar(
                progress_bar_energy_x,
                progress_bar_energy_y,
                progress_bar_energy_width,
                progress_bar_energy_height,
        
                value_energy_max,
                unit_energy
            );

            gui_elements.container_main:child_add( gui_elements.progress_bar_energy );


            gui_elements.border_progress_bar_energy = graphics.draw_border(
                progress_bar_energy_x - 1,
                progress_bar_energy_y - 1,
                progress_bar_energy_width + 2,
                progress_bar_energy_height + 2,

                "STATUS N/A",

                colors.border,
                colors.black,
                colors.foreground
            );

            gui_elements.container_main:child_add( gui_elements.border_progress_bar_energy );
            
        --[[ ENERGY PROGRESS BAR END ]]--




        --[[ PROGNOSIS LABEL ]]--

            --[[
            local label_prognosis_width = res_x - 2;
            local label_prognosis_height = 1;
            local label_prognosis_x = x + 1;
            local label_prognosis_y = histogram_energy_io_y_max + 1;

            gui_elements.label_prognosis = graphics.label(
                label_prognosis_x,
                label_prognosis_y,
                label_prognosis_width,
                label_prognosis_height,

                "TESTING",
    
                colors.primary, --- Background
                colors.foreground --- Label
            );
            ]]--
        
        --[[ PROGNOSIS LABEL ]]--

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

function display_loop()

    --[[ Induction Matrix data gathering ]]--

        matrix_ready = type( matrix.getEnergy() ) ~= "string";

        if not matrix_ready then

            label_energy_prognosis = {
                label = "ERROR: NOT ASSEMBLED",
                color = colors.red
            };

            table.insert(values_out, 1, 0);
            table.insert(values_in, 1, 0);

            return display_draw();

        end


        table.insert(values_out, 1, matrix.getOutput() * unit_factor);
        table.insert(values_in, 1, matrix.getInput() * unit_factor);

        value_io_max = matrix.getTransferCap() * unit_factor;
        value_energy_max = matrix.getMaxEnergy() * unit_factor;
        value_energy = matrix.getEnergy() * unit_factor;

        --- Reduce to amount of visible values + buffer of 5
        utils.table.remove_overflow(values_out, values_io_count + values_io_count_buffer);
        utils.table.remove_overflow(values_in, values_io_count + values_io_count_buffer);


        local value_io = values_in[1] - values_out[1];
        if value_io == 0 then

            --- io is same so no storage change
            label_energy_prognosis = {
                label = "STABLE",
                color = colors.yellow
            };

        elseif value_io > 0 then

            --- more in that out so will be filled in...
            local time_energy_full = (value_energy_max - value_energy) / value_io; --- How many ticks it takes to fill storage at current input
            label_energy_prognosis = {
                label = "FILLED IN: " .. utils.time.format_seconds(time_energy_full / 20),
                color = colors.green
            };

        elseif value_io < 0 then

            --- more out than in so will be drained in...
            local time_energy_empty = value_energy / math.abs(value_io); --- How many ticks it takes to drain storage at current output
            label_energy_prognosis = {
                label = "DRAINED IN: " .. utils.time.format_seconds(time_energy_empty / 20),
                color = colors.red
            };

            
        end

    --[[ Induction Matrix data gathering end ]]--



    
    display_draw();

end

function display_draw()

    --[[ GUI elements draw ]]--

        --[[ ENERGY I/O HISTOGRAMS ]]--

            gui_elements.histogram_energy_in.values = values_in;
            gui_elements.histogram_energy_in:redraw();

            gui_elements.histogram_energy_out.values = values_out;
            gui_elements.histogram_energy_out:redraw();

        --[[ ENERGY I/O HISTOGRAMS END ]]--




        --[[ ENERGY PROGRESS BAR ]]--

            gui_elements.progress_bar_energy.value_current = value_energy;
            gui_elements.progress_bar_energy:redraw();

            gui_elements.border_progress_bar_energy.label = label_energy_prognosis.label;
            gui_elements.border_progress_bar_energy.color_label = label_energy_prognosis.color;
            gui_elements.border_progress_bar_energy:redraw();

        --[[ ENERGY PROGRESS BAR END ]]--




        --[[ PROGNOSIS LABEL ]]--

            --gui_elements.label_prognosis:redraw();

        --[[ PROGNOSIS LABEL END ]]--



        --gui_elements.container_main:redraw();

    --[[ GUI elements draw end ]]--

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


    data_send({
        id = modem.address:sub(1, 5), -- TODO: id of matrix (implement id's for base structures in general)
        energy = value_energy or 0,
        energy_max = value_energy_max or 0,
        energy_in = values_in[ 1 ] or 0,
        energy_out = values_out[ 1 ] or 0,
        energy_io_max = value_io_max or 0
    });


    -- TODO: implement lights indicating rough energy level (100% - dark green; <75% - light green; <50% - yellow; <25% - orange; <10% - red)

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
  
  

    --- Configure modem
    logger:info("Configuring modem...");

        modem.open( constants.port.energy );
            logger:info("Modem port 'ENERGY:" .. constants.port.energy .. "' opened.\n");

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

        modem.close( constants.port.energy );
            logger:info("Modem port 'ENERGY:" .. constants.port.energy .. "' closed.");

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