--[[
    DNS-Server
    DNS-Server component of network cluster structure
    A DNS-Server acts as hostname/address resolver, thus holding tables
    of hostnames associated with network addresses and vice versa.
--]]


-- Libraries and components
local codec = require("cluster/codec");
local Config = require("cluster/config");
local constants = require("cluster/constants");
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

-- Files and Configurations
local file_log = "/var/log/cluster/node-dns.log"; -- TODO: create new file at every startup?


local file_dns_entries = "/etc/dns_entries.cfg";
local file_dns_entries_reverse = "/etc/dns_entries_reverse.cfg";

local dns_entries = Config:create( file_dns_entries );
local dns_entries_reverse = Config:create( file_dns_entries_reverse );
--

-- Data tables
local operations = {}; --- Convenience table holding operations applicable to DNS entries
--




--<< Data Handling >>--

--- Receives data packets from network cluster, passed through by Common Node via 'cluster_data' event
function data_handle(_, _packet_request)

    local packet_request = Packet:decode( _packet_request );
    if packet_request.port ~= constants.port.dns then return; end



    local client = packet_request.sender;
    local operation = packet_request.data.operation;
    local entry = packet_request.data.entry or "unknown";
    local address = packet_request.data.address or client;
    local option = packet_request.data.option;

    logger:info("Client '" .. tostring( select(2, operations.query( client )) or client ) .. "' requested '" .. tostring( operation ) .. "' on '" .. tostring( entry ) .. "'" .. (option and (" with option '" .. tostring(option) .. "'") or ""));

    

    local response = {
        success = false,
        result = "Undefined"
    };


    response.success, response.result = operations[ operation ](entry, address, option);


    
    Packet:create(
        modem.address,
        client,
        packet_request.port,
        constants.packet.response,
        response
    ):send();

    logger:info("Response to client '"  .. tostring( select(2, operations.query( client )) or client ) ..  "': '" .. tostring( response.success ) .. " - " .. tostring( response.result ) .. "'\n");

end

--- Sends internal data to Core, passed through by Common Node via internal_data event
function data_send(data)
    
    event.push("internal_data", codec.encode( data )); -- TODO: data size and type etc.
    
end

--<< Data Handling end >>--




--<< Node Functions >>--

--- Load DNS entries from disk
function entries_load()

    local success_dns_entries, result_dns_entries = dns_entries:load();

    local success_dns_entries_reverse, result_dns_entries_reverse = dns_entries_reverse:load();


    return {
        dns_entries = {
            success = success_dns_entries,
            result = result_dns_entries
        },
        dns_entries_reverse = {
            success = success_dns_entries_reverse,
            result = result_dns_entries_reverse
        }
    };

end

--- Save DNS entries to disk
function entries_save()

    local success_dns_entries, result_dns_entries = dns_entries:save();

    local success_dns_entries_reverse, result_dns_entries_reverse = dns_entries_reverse:save();

    
    local result_save = {
        dns_entries = {
            success = success_dns_entries,
            result = result_dns_entries
        },
        dns_entries_reverse = {
            success = success_dns_entries_reverse,
            result = result_dns_entries_reverse
        }
    };

    return result_save;

end

--- Check whether a DNS entry exists. Note that 'entry' can be either hostname or an address
function operations.exists(entry)
    
    entry = entry:lower();


    local result = dns_entries:get( entry, {reload = true} );
    local result_reversed = dns_entries_reverse:get( entry, {reload = true} );

    if result or result_reversed then

        return true, result or result_reversed;

    else
        
        return false, nil;

    end

end

--- Create a new DNS entry
function operations.create(name, address)

    name = name:lower();
    address = address:lower();
    

    if operations.exists( name ) then

        return false, "Hostname already exists";

    else

        dns_entries:set(name, address);
        dns_entries_reverse:set(address, name);

        entries_save();


        return true, address;
        
    end

end

--- Delete a existing DNS entry. Note that 'entry' can be either hostname or an address
function operations.delete(entry)

    entry = entry:lower();


    --- Returns whether entry exists and if, returns associated value. Note that this works for 'entry' being a hostname or an address, thus making 'result' the opposite of what 'entry' is
    local exists, result = operations.exists( entry );

    if exists then

        --- Set both entry and result to nil in both configs to make sure both cases (entry:hostname with result:address AND entry:address, result:hostname) are covered
        dns_entries:set(entry, nil);
        dns_entries:set(result, nil);

        dns_entries_reverse:set(entry, nil);
        dns_entries_reverse:set(result, nil);


        return true, result;

    else

        return false, "No existing entry";

    end

end

--- Query for DNS entry. Note that 'entry' can be either hostname or an address
function operations.query(entry)

    return operations.exists( entry );

end

--- Edit an existing DNS entry
function operations.edit(name, address, name_new)

    name = name:lower();
    address = address:lower();
    name_new = name_new:lower();

    if operations.delete( name ) then

        dns_entries:set(name_new, address);
        dns_entries_reverse:set(address, name_new);

        entries_save();


        return true, address;

    else

        return false, "No existing entry";
        
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
function loop()
    
    data_send( dns_entries.contents );

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



    --- Load DNS entries
    logger:info("Loading DNS entries from disk...");

        local result_entries_load = entries_load();


        if result_entries_load.dns_entries.success then

            logger:info("Loaded DNS entries.");

        else

            logger:error("DNS entries could not be loaded: " .. tostring( result_entries_load.dns_entries.result ));

        end

        if result_entries_load.dns_entries_reverse.success then

            logger:info("Loaded reverse DNS entries.");

        else

            logger:error("Reverse DNS entries could not be loaded: " .. tostring( result_entries_load.dns_entries_reverse.result ));

        end

    logger:info("Done.\n");
    --- Load DNS entries end

    
    
    --- Configure modem
    logger:info("Configuring modem...");

        modem.open( constants.port.dns );
            logger:info("Modem port 'DNS:" .. constants.port.dns .. "' opened.\n");

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

end

--- Main shutdown function, executed once at shutdown
function shutdown()

    local time_shutdown = computer.uptime();
  

    logger:info("----- SHUTDOWN -----", false);
    logger:info("Shutting down...\n");



    --- Save DNS entries
    logger:info("Saving DNS entries to disk...");

        entries_save();

    logger:info("Done.\n");
    --- Save DNS entries end



    --- Configure modem
    logger:info("Configuring modem...");

        modem.close( constants.port.dns );
            logger:info("Modem port 'DNS:" .. constants.port.dns .. "' closed.");

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