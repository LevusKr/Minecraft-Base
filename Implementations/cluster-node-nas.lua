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
local dns = require("cluster/dns-library");
local Logger = require("cluster/logger");
local Packet = require("cluster/network_packet");
local Stats = require("cluster/stats");
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
local cache_files = {}; --- In-memory metadata/hash/chunk cache indexed by file path, validated via last_modified and size

local stats = Stats.create("node-nas");
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if packet_request.port ~= constants.port.file then return; end



    local client_address = packet_request.sender;
    local client = client_address;
    local operation = packet_request.data.operation or "info";
    local file = packet_request.data.file or ".nas-info";
    local options = packet_request.data.options or {};
    local content = packet_request.data.content;

    -- TODO: if dns is unrechable, this adds extra timeout duration on uncached nodes. but dns is critical so should never fail
    local dns_success, dns_result = dns.lookup( client_address );

    if dns_success and dns_result then
        client = dns_result;
    end

    logger:info("Client '" .. tostring( client ) ..
        "' requested operation '" .. tostring( operation ) ..
        "' on file '" .. tostring( file ) .. 
        "' with options '" .. codec.encode( options ) ..
        "'"
    );
    if content then
        local content_preview = tostring( utils_string.dotate(content, 32) ):gsub("\r", ""):gsub("\n", "\\n");
        logger:info("New file content: '" .. content_preview .. "'");
    end

    stats:record_request(client, operation, #_packet_request);
    if file and file ~= ".nas-info" then
        stats:record_detail("file", file);
    end



    local response = {
        success = false,
        result = "Undefined"
    };


    response.success, response.result = operations[ operation ](file, options, content);



    local packet_response = packet_request:create_response( response );

    local send_success, send_result = packet_response:send();

    if send_success then
        logger:info("Response to client '"  .. tostring( client ) ..  "': '" .. tostring( response.success ) .. " - " .. tostring( utils_string.dotate(codec.encode(response.result), 100) ) .. "'\n");

        stats:record_response(response.success, packet_response:size());
    else
        logger:error("Response to client '"  .. tostring( client ) ..  "' couldn't be sent: " .. tostring( send_result ) .. "\n");

        stats:record_error(client, operation, send_result);
    end

end

--- Sends internal data to Core, passed through by Common Node via internal_data event
function data_send(data)
    
    event.push("internal_data", data); -- TODO: data size and type etc.
    
end

--<< Data Handling end >>--




--<< Node Functions >>--

function operations.stats()
    return true, stats:export();
end

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

--- Resolves a virtual NAS file path to its physical RAID path without duplicate slashes
local function resolve_raid_path(file)

    if utils_file.join_path then
        return utils_file.join_path(path_raid, tostring( file or "" ));
    end

    return path_raid .. tostring( file or "" ):gsub("^/+", "");

end

--- Ensures all parent directories of a physical RAID path exist
local function ensure_parent_directory(path)

    local dir = filesystem.path( path );

    if not dir or dir == "" or filesystem.exists( dir ) then
        return;
    end

    if utils_file.mkdir then

        utils_file.mkdir( dir );

    else

        local segments = filesystem.segments( dir );
        local current = "";

        for _, segment in ipairs( segments ) do

            current = current .. "/" .. segment;

            if not filesystem.exists( current ) then
                filesystem.makeDirectory( current );
            end

        end

    end

end

--- Opens handle for given file. Optionally open file in binary mode via 'options.binary'
function operations.open(file, options)

    options = options or {};


    local path = resolve_raid_path( file );
    local handle = handles[ path ];

    if not handle then

        if options.mode == "w" or options.mode == "a" then
            ensure_parent_directory( path );
        end

        handle = io.open(path, (options.mode or "r") .. (options.binary and "b" or ""));

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


    local path = resolve_raid_path( file );
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


    local path = resolve_raid_path( file );
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


    local path = resolve_raid_path( file );
    local handle = handles[ path ];

    if not handle then
        ensure_parent_directory( path );
    end

    local success, result, handle = utils_file.write(
        handle or path,
        content,
        options
    );

    handles[ path ] = handle;
    cache_files[ file ] = nil;
    

    return success, result;

end

--- Checks whether given file exists
function operations.exists(file)

    local success = filesystem.exists( resolve_raid_path( file ) );

    if success then
        
        return true, "Exists";

    end

    return false, "Not existing";

end

--- Checks whether given file is a directory
function operations.is_directory(file)

    local success = filesystem.isDirectory( resolve_raid_path( file ) );

    if success then
        
        return true, "Directory";

    end

    return false, "No directory";

end

--- Creates given file if non-existent
function operations.create(file)

    local success, result = false, "Already existing";
    
    if not filesystem.exists( resolve_raid_path( file ) ) then

        success, result = operations.write(file, _, "");

    end
    
    
    return success, result;

end

--- Removes given file if existent
function operations.remove(file)

    local success, result = false, "Not existing";


    local path = resolve_raid_path( file );

    if filesystem.exists( path ) then

        success, result = filesystem.remove( path );

        if success then

            cache_files[ file ] = nil;

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

    local result = filesystem.size( resolve_raid_path( file ) );

    
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

    local result = filesystem.lastModified( resolve_raid_path( file ) );

    return utils.format.tuple( result );

end

--- Retrieves cached file metadata/hash (validated via filesystem.lastModified), reading disk only when needed
local function get_file_cached(file, need_content, need_chunks)

    local path = resolve_raid_path( file );
    local last_modified = filesystem.lastModified( path );

    if not last_modified or last_modified == 0 then

        cache_files[ file ] = nil;
        return false, nil;

    end


    local cached = cache_files[ file ];

    if cached and cached.last_modified == last_modified then

        local content = cached.content;

        if (need_content or (need_chunks and not cached.chunks)) and not content then

            content = utils_file._read(path, true);

            if not content then
                return false, nil;
            end

        end

        if need_chunks and not cached.chunks and content then

            cached.chunks = utils_file.chunk( content );
            cached.chunk_hashes = utils_file.hash_chunks( cached.chunks );

        end


        return true, cached, content;

    end


    local content = utils_file._read(path, true);

    if content == nil then
        return false, nil;
    end


    local file_hash =
        utils_file.hash
        and select(1, utils_file.hash(content, true))
        or data.crc32( content )
    ;

    cached = {
        last_modified = last_modified,
        size          = #content,
        hash          = file_hash,
        chunks        = nil,
        chunk_hashes  = nil
    };

    if need_chunks then

        cached.chunks = utils_file.chunk( content );
        cached.chunk_hashes = utils_file.hash_chunks( cached.chunks );

    end

    cache_files[ file ] = cached;


    return true, cached, content;

end

--- Compares given file checksums with local corresponding files checksums and return equality. Optionally return new file content or delta via 'options.download'
function operations.compare(files, options)

    options = options or {};

    if options.invalidate then
        cache_files = {};
    end


    local success = false;
    local result = {};
    local hashes = {};
    local summary = {
        total      = 0,
        up_to_date = 0,
        updated    = 0,
        delta      = 0,
        full       = 0,
        missing    = 0,
        bytes      = 0,
        saved      = 0
    };

    if type( files ) == "table" then

        --- Support both dictionary {"/path" = hash_or_table} and legacy array {{file = "/path", hash = "..."}}
        local normalized_files = {};

        if files[1] and type( files[1] ) == "table" and files[1].file then

            for _, item in ipairs( files ) do
                normalized_files[ item.file ] = item.hash or false;
            end

        else

            normalized_files = files;

        end


        for entry_file, entry_info in pairs( normalized_files ) do

            summary.total = summary.total + 1;

            local entry_hash =
                type( entry_info ) == "table"
                and entry_info.hash
                or entry_info
            ;
            local entry_chunks =
                type( entry_info ) == "table"
                and entry_info.chunks
                or nil
            ;

            local file_exists, cached = get_file_cached(entry_file, false, false);

            --- If file without extension was requested and '.lua' exists on NAS, resolve to '.lua'
            if (not file_exists or not cached) and type( entry_file ) == "string" and not entry_file:match("%.[%w_]+$") then

                local lua_exists, lua_cached = get_file_cached(entry_file .. ".lua", false, false);

                if lua_exists and lua_cached then

                    entry_file = entry_file .. ".lua";
                    file_exists = lua_exists;
                    cached = lua_cached;

                end

            end

            if not file_exists or not cached then

                summary.missing = summary.missing + 1;
                result[ entry_file ] = nil;

            elseif options.hashes_only then

                result[ entry_file ] = cached.hash;
                hashes[ entry_file ] = cached.hash;

            else

                hashes[ entry_file ] = cached.hash;

                local file_equal =
                    (not options.force)
                    and (entry_hash ~= false)
                    and (entry_hash ~= nil)
                    and (cached.hash == entry_hash)
                    or false
                ;

                if file_equal then

                    summary.up_to_date = summary.up_to_date + 1;
                    result[ entry_file ] = true;

                elseif options.download then

                    local want_delta = (options.delta ~= false) and (type( entry_chunks ) == "table") and (#entry_chunks > 0);
                    local _, cached_full, file_content = get_file_cached(entry_file, true, want_delta);

                    if cached_full and file_content then

                        local delta_applied = false;

                        if want_delta and cached_full.chunks and cached_full.chunk_hashes then

                            local delta_ok, delta_ops, bytes_saved = utils_file.compute_delta(
                                entry_chunks,
                                cached_full.chunks,
                                cached_full.chunk_hashes,
                                #file_content
                            );

                            if delta_ok then

                                result[ entry_file ] = {
                                    delta = true,
                                    hash  = cached_full.hash,
                                    size  = #file_content,
                                    saved = bytes_saved,
                                    ops   = delta_ops
                                };

                                summary.updated = summary.updated + 1;
                                summary.delta = summary.delta + 1;
                                summary.bytes = summary.bytes + math.max(0, #file_content - bytes_saved);
                                summary.saved = summary.saved + bytes_saved;
                                delta_applied = true;

                            end

                        end

                        if not delta_applied then

                            result[ entry_file ] = {
                                delta   = false,
                                hash    = cached_full.hash,
                                size    = #file_content,
                                content = file_content
                            };

                            summary.updated = summary.updated + 1;
                            summary.full = summary.full + 1;
                            summary.bytes = summary.bytes + #file_content;

                        end

                    else

                        summary.missing = summary.missing + 1;
                        result[ entry_file ] = nil;

                    end

                else

                    result[ entry_file ] = false;

                end

            end

        end

        success = true;

    end


    --- If a direct recipient (client) was specified by the Update-Server, send the heavy payload directly to the client
    if success and options.recipient and type( options.recipient ) == "table" and options.recipient.address and options.recipient.id then

        local packet_direct = Packet.create(
            modem.address,
            options.recipient.address,
            options.recipient.port or constants.port.update,
            constants.packet.response,
            {
                id      = options.recipient.id,
                success = true,
                direct  = true,
                summary = summary,
                result  = result
            }
        );

        local direct_success, direct_error = packet_direct:send();

        local recipient_label = tostring( options.recipient.name or options.recipient.address );

        if direct_success then

            logger:info("Directly transferred update payload to client '" .. recipient_label .. "' (" .. tostring( summary.updated ) .. " updated, " .. tostring( summary.delta ) .. " delta, " .. utils.math.adjust_value(summary.bytes, "B") .. ").");

            stats:record_response(true, packet_direct:size());

            return true, {
                forwarded = true,
                recipient = options.recipient.address,
                summary   = summary,
                hashes    = hashes
            };

        else

            logger:warn("Direct transfer to client '" .. recipient_label .. "' failed (" .. tostring( direct_error ) .. "). Falling back to Update-Server tunnel.");

        end

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

        -- if component.isAvailable("raid") then

            mounted, message = filesystem.mount(filesystem.proxy("raid"), path_raid);

        -- end

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