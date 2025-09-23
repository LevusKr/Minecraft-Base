--[[
    NAS-Server
    NAS-Server component of network cluster structure
    A NAS acts as network proxy of a filesystem (e.g. raid), thus accepting all
    filesystem api calls over network and response with corresponding data.
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-nas.log"; -- TODO: create new file at every startup? -> general log redesign (see log-daemon.lua)

local path_raid = "/net/";
--

-- Libraries and components
local codec = require("cluster/codec");
local constants = require("cluster/constants");
local Logger = require("cluster/logger");
local Packet = require("cluster/network_packet");
local utils = require("cluster/utils");
local utils_file = require("cluster/utils-file");
local utils_string = require("cluster/utils-string");

local component = require("component");
local computer = require("computer");
local event = require("event");
local filesystem = require("filesystem");
local os = require("os");
local term = require("term");
local thread = require("thread");


local modem = component.modem;
local data = component.data;
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
--

-- Data tables
local operations = {}; --- Convenience table holding operations applicable to NAS files

local handles = {};
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if packet_request.port ~= constants.port.file then return; end



    local client = packet_request.sender;
    local operation = packet_request.data.operation or "info";
    local file = packet_request.data.file or ".nas-info";
    local options = packet_request.data.options or {};
    local content = packet_request.data.content;

    logger:info("Client '" .. tostring( client ) ..
        "' requested operation '" .. tostring( operation ) ..
        "' on file '" .. tostring( file ) ..
        "' with options '" .. codec.encode( options ) ..
        "'"
    );
    if content then
        logger:info("New file content: '" .. tostring( utils_string.dotate(content, 32) ) .. "'\n");
    end



    local response = {
        success = false,
        result = "Undefined"
    };


    response.success, response.result = operations[ operation ](file, options, content);



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

--<< Data Handling end >>--




--<< Node Functions >>--

--- Compose information for given file. Optionally define specific critera in 'options'
function operations.info(file, options)

    --- Set all criterias to 'true' by default
    -- TODO: change
    options = {
        exists        = (options.exist         == nil) and true or options.exist,
        is_directory  = (options.is_directory  == nil) and true or options.is_directory,
        size          = (options.size          == nil) and true or options.size,
        last_modified = (options.last_modified == nil) and true or options.last_modified
    };

    print(options.size) -- TODO: remove


    local info = {};

    for option, value in pairs( options ) do

        --- 'success_execution' is pcall success
        --- 'result_execution' is either pcall's error message or success of operation
        --- 'result' is either nil or result of operation
        local success_execution, result_execution, result = pcall(operations[ option ], file);

        info[ option ] = {
            success = success_execution and result_execution or false,
            result = success_execution and result or result_execution;
        }

    end


    return true, info;

end

--- Opens handle for given file. Optionally open file in binary mode via 'options.binary'
function operations.open(file, options)

    options = options or {};


    local path = path_raid .. tostring( file );
    local handle = handles[ path ];

    if not handle then

        handle = io.open(path, options.mode .. (options.binary and "b" or ""));

        if not handle then

            return false, "File not found";

        end

    end

    handles[ path ] = handle;


    return true, file;

end

--- Closes handle for given file.
function operations.close(file, options)

    options = options or {};


    local path = path_raid .. tostring( file );
    local handle = handles[ path ];

    if not handle then

        return true, "Not open";

    end

    handle:flush();
    handle:close();

    handles[ path ] = nil;


    return true, file;

end

--- Reads file content from given file. Optionally open file in binary mode via 'options.binary'
function operations.read(file, options)

    options = options or {};


    local path = path_raid .. tostring( file );
    local handle = handles[ path ];

    local success, result, handle = utils_file.read(
        handle or path,
        options
    );

    handles[ path ] = handle;


    return success, result;

end

--- Writes new content to given file. Optionally open file in binary and/or append mode via 'options.binary' and 'options.append'
function operations.write(file, options, content)

    options = options or {};


    local path = path_raid .. tostring( file );
    local handle = handles[ path ];

    local success, result, handle = utils_file.write(
        handle or path,
        content,
        options
    );

    handles[ path ] = handle;
    

    return success, result;

end

--- Checks whether given file exists
function operations.exists(file)

    local success = filesystem.exists(path_raid .. tostring( file ));

    if success then
        
        return true, "Exists";

    end

    return false, "Not existing";

end

--- Checks whether given file is a directory
function operations.is_directory(file)

    local success = filesystem.isDirectory(path_raid .. tostring( file ));

    if success then
        
        return true, "Directory";

    end

    return false, "No directory";

end

--- Creates given file if non-existent
function operations.create(file)

    local success, result = false, "Already existing";
    
    if not filesystem.exists(path_raid .. tostring( file )) then

        success, result = operations.write(file, _, "");

    end
    
    
    return success, result;

end

--- Removes given file if existent
function operations.remove(file)

    local success, result = false, "Not existing";


    local path = path_raid .. tostring( file );

    if filesystem.exists( path ) then

        success, result = filesystem.remove( path );

        if success then

            result = "Removed"; --- 'filesystem.remove' returns no result when succeeding, but we want some message

        else

            success = false; --- 'filesystem.remove' returns 'nil' and an error when failing, but we want 'false' as success indicator

        end

    end



    return success, result;

end

--- Lists files at given path
function operations.list(path)

    if path == "" then path = "/"; end

    local success, result = utils_file.list(tostring( path ), path_raid);

    
    return success, result;

end

--- Retrieves given file's size
function operations.size(file)

    local result = filesystem.size(path_raid .. tostring( file ));

    
    return utils.format.tuple( result );

end

--- Retrieve free space
function operations.space_free()

    local success_total, result_total = operations.space_total();
    local success_used, result_used = operations.space_used();

    if not success_total then

        return false, result_total;

    elseif not success_used then

        return false, result_used;

    end


    local result = result_total - result_used;

    return utils.format.tuple( result );

end

--- Retrieve used space
function operations.space_used()

    local filesystem_raid = filesystem.get( path_raid );

    if not filesystem_raid then

        return false, "No valid filesystem";

    end


    local result = filesystem_raid.spaceUsed();


    return utils.format.tuple( result );

end

--- Retrieve total space
function operations.space_total()

    local filesystem_raid = filesystem.get( path_raid );

    if not filesystem_raid then

        return false, "No valid filesystem";

    end


    local result = filesystem_raid.spaceTotal();

    return utils.format.tuple( result );

end

--- Retrieves given file's date of last modification
function operations.last_modified(file)

    local result = filesystem.lastModified(path_raid .. tostring( file ));

    return utils.format.tuple( result );

end

--- Compares given file checksums with local corresponding files checksums and return equality. Optionally return new file content via 'options.download'
function operations.compare(files, options)

    local success = false;
    local result = {};

    if type( files ) == "table" then

        for entry_file, entry_hash in pairs( files ) do

            local file_exists, file_content = operations.read(entry_file, {binary = true});
            local file_equal =
                file_exists
                and (data.crc32( file_content ) == entry_hash)
                or false
            ;

            
            if options.download and not file_equal and file_exists then

                logger:warn("deflate file content")
                os.sleep(0.25)
    
                result[ entry_file ] = data.deflate( file_content ); --- New file content {"file_name" = *file content*}
    
            else
    
                result[ entry_file ] = file_equal; --- Equality {"file_name" = true/false}
    
            end
    
        end

        success = true;

    end


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

    --

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



    --- Search for available raid
    logger:info("Searching for available raid to mount...");

        local mounted, message = false, "No raid found";

        if component.isAvailable("raid") then

            mounted, message = filesystem.mount(filesystem.proxy("raid"), path_raid);

        end

        if mounted then

            logger:info("Successfully mounted raid at '" .. path_raid .. "'.");

        else

            logger:error("Unable to mount raid: " .. tostring( message ));

        end

    logger:info("Done.\n");
    --- Search for available raid end



    --- Configure modem
    logger:info("Configuring modem...");

        modem.open( constants.port.file );
            logger:info("Modem port 'FILE:" .. constants.port.file .. "' opened.\n");

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



    local time_startup_finished = computer.uptime() - time_startup;
    logger:info("Successfully started up in " .. time_startup_finished .. " seconds.\n\n");




    --- When updating manually via /bin/update.lua cli, /home/cluster-node-nas.lua won't be running so the update server won't reach cluster-node-nas, thus leading to manual updating failing
    --- So we disabled update at startup and rather update after startup of /home/cluster-node-nas.lua (this program)
    --os.execute("update true");

end

--- Main shutdown function, executed once at shutdown
function shutdown()
    local time_shutdown = computer.uptime();
  

    logger:info("----- SHUTDOWN -----", false);
    logger:info("Shutting down...\n");



    --- Configure modem
    logger:info("Configuring modem...");

        modem.close( constants.port.file );
            logger:info("Modem port 'FILE:" .. constants.port.file .. "' closed.");

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



    local time_shutdown_finished = computer.uptime() - time_shutdown;
    logger:info("Successfully shut down in " .. time_shutdown_finished .. " seconds.");




    logger:close({rotate=false});
    --logger:transfer();
    running = false;

    os.exit(0);


    -- TODO: tell common node to disconnect?
end

--<< Main Functions end >>--




startup();

local success, result = thread.waitForAny({thread_interrupt_handler});

shutdown();