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
local file_log = "/var/log/node-%s.log";
--

-- Libraries and components
local Logger = require("cluster/logger");
local utils = require("cluster/utils");

local component = require("component");
local event = require("event");


local modem = component.modem;
--

-- Variables and constants
local logger = nil;
local log_print = true;
local log_debug = true;
local log_buffer = true; -- whether buffer logs or not

local hostname = nil;

local timer_loop = 0;
--

-- Data tables
local loggers = {};
--




function logger_create(name, file, print, print_debug, print_verbose, use_buffer) -- create logger handle

	local logger_init_success, logger_init_result = Logger.create(
        name,
        file,
        print,
        print_debug,
        print_verbose,
        use_buffer
    );


    if not logger_init_success then

		-- TODO: don't error out, instead hand error message to caller
    	error("Error whilst initializing logger: " .. tostring( logger_init_result ));

    end


	loggers.name = logger_init_result;

end

function logger_rotate(name)

	if loggers.name then

		loggers.name:rotate();

	end

end

function logger_transfer(name)

	if loggers.name then

		loggers.name:transfer();

	end

end




local function tick()
  --
end

function start()
  utils.logging.info("Starting up...", file_log);
  
  -- startup stuff
  event.listen("logger_create", logger_create); -- daemon (sub-daemon?) for receiving network messages
  
  --timer_loop = event.timer(1, tick, math.huge); -- start tick loop execution
end

function stop()
  utils.logging.info("Shutting down...", log_local);  
  
  -- shutdown stuff   TODO: send logs to server
  
  --event.cancel(timer_loop);
end