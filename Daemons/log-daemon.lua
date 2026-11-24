--[[
    Log-Daemon
    This daemon provides functionality to create local log files.
    Use proper library implementation for sending internal signals via event.push(...) (log-library.lua).


    Send logs directly to Server
		-> Optional: Still save logs locally aswell as remotely (can be toggled to [remote; local])
    Buffer in memory or disk 
		-> Send every x seconds  /  n logs
        OR at program exit
    Programs save logs local like they don't care about disk space, availability etc.
		-> log-daemon later accepts requests from log-server for handing over n amount of logs  /  t time span of logs etc.
			This will result in high disk usage but less strain on network and server resources.
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/daemon-log.log";
--

-- Libraries and components
local Logger = require("cluster/logger");

local event = require("event");
--

-- Variables and constants
local logger = nil;
local log_print = false;
local log_debug = false;
local log_verbose = false;
local log_buffer = true;

local running = false;
--

-- Data tables
local loggers = {};
--




--<< Daemon Functions >>--

--- Creates and registers a managed logger handle
function logger_create(_, name, file, print, print_debug, print_verbose, use_buffer)

    if not name or not file then

        return false, "Missing logger name or file path";

    end


    local logger_init_success, logger_init_result = Logger.create(
        name,
        file,
        print,
        print_debug,
        print_verbose,
        use_buffer
    );

    if not logger_init_success then

        if logger then

            logger:error("Error whilst initializing logger '" .. tostring( name ) .. "': " .. tostring( logger_init_result ));

        end

        return false, logger_init_result;

    end


    loggers[ name ] = logger_init_result;


    return true, logger_init_result;

end

--- Rotates a managed logger by name
function logger_rotate(_, name)

    if name and loggers[ name ] then

        return loggers[ name ]:rotate();

    end

    return false, "Logger not found";

end

--- Transfers a managed logger by name
function logger_transfer(_, name, options)

    if name and loggers[ name ] then

        return loggers[ name ]:transfer( options );

    end

    return false, "Logger not found";

end

--<< Daemon Functions end >>--




--<< RC Lifecycle >>--

function start()

    if running then

        return false, "Already running";

    end


    local success_log, result_log = Logger.create(
        "daemon-log",
        file_log,
        log_print,
        log_debug,
        log_verbose,
        log_buffer
    );

    if success_log then

        logger = result_log;
        logger:info("Starting up...");

    end


    event.listen("logger_create", logger_create);
    event.listen("logger_rotate", logger_rotate);
    event.listen("logger_transfer", logger_transfer);

    running = true;

    if logger then

        logger:info("Started.");

    end

end

function stop()

    if not running then

        return false, "Not running";

    end


    event.ignore("logger_create", logger_create);
    event.ignore("logger_rotate", logger_rotate);
    event.ignore("logger_transfer", logger_transfer);


    for _, managed_logger in pairs( loggers ) do

        managed_logger:close();
        managed_logger:transfer();

    end

    loggers = {};
    running = false;


    if logger then

        logger:info("Shutting down...");
        logger:close();
        logger:transfer();

    end

end

--<< RC Lifecycle end >>--