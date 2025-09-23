--[[
    Space-Station
    Space-Station component of network cluster structure
    A Space-Station acts as representation of a extraterrestial space station, thus sending local statistics, e.g. from life support system, energy production etc.
    and receiving (and displaying) general information, e.g.

    TODO: what should we even receive? since launch control is handled somewhere else...
    TODO: this probably should handle the various nodes present on the space station, which would need to be added to some sort of watchlist
    TODO: this node then watches the registered nodes data packets and provides a centralized way of watching and possibly controlling them
    TODO: e.g. oxygen/energy production, consumption and distribution, airlocks, oxygen seals, meteor deflection
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-%s.log"; -- TODO: create new file at every startup?
--

-- Libraries and components
local component = require("component");
local computer = require("computer");
local event = require("event");
local os = require("os");
local term = require("term");
local thread = require("thread");
local utils = require("cluster/utils");

local modem = component.modem; -- primary modem
--

-- Variables and constants
local logger = nil;
local log_print = true;
local log_debug = true;
local log_buffer = true; -- whether buffer logs or not

local hostname = nil;

local timer_loop = 0; -- timer id of main loop
--



-- Receives internal data from Core, passed through by Node via cluster_data event
function data_handle(_, data)
  local packet = select(2, utils.encoding.decode(data))
  if packet.port ~= constants.port.space_station then return; end -- TODO: change port when changed in utils.lua


  local action = packet.data.action; -- data to process
  local response = {};

  logger:info("Client '"..packet.sender.."' requested '"..tostring(action).."'...");
  local callback = function(_, _, _packet_response) -- implement call and callback
    local packet_response = select(2, utils.encoding.decode(_packet_response));
    
    response = packet_response.data.response;
    utils.network.send_packet(packet.sender, packet.port, constants.packet.ack, {id = packet.id, response = response}); -- forward internal call to caller
    
    logger:info("Sent response: '"..tostring(response).."'");
  end
end

-- Sends internal data to Core, passed through by Node via internal_data event
function data_send(data)
  event.push("internal_data", data); -- TODO: data size and type etc.
end



-- Threads --
-- Thread for handling program interruption
local thread_interrupt = thread.create(
  function()
    print("before interrupted")
    event.pull("interrupted"); -- wait until interrupt event
    print("after interrupted")
    running = false; -- mark execution as not running
  end
);
--


-- Main Functions --
function loop() -- Main loop function, executed once every second
end

function startup() -- Main startup function, executed once at startup
  local time_startup = computer.uptime();

  running = true; -- mark execution as running
  hostname = utils.internal.hostname(); -- read hostname from /etc/hostname
  file_log:format(hostname); -- set log file to hostname (multiple instances possible, so not differ by node-space_station only, but node-space_station-orbit_earth, ...)
  logger = utils.logging.logger(hostname, file_log, log_print, log_debug, log_buffer);


  term.clear(); -- clear previous stuff
  logger:info("----- STARTUP -----", false);
  logger:info("Starting up...\n");
  
  

  logger:info("Checking if node is connected to core...");
    -- check wether common node daemon is connected to the core   TODO: shutdown etc.
    if not os.getenv(constants.env.connected) then shutdown(); end -- if not connected print error and shutdown gracefully
  logger:info("Done.\n");



  logger:info("Implement");
  logger:info("Done.\n");
  
  

  logger:info("Configuring modem...");
    modem.open(constants.port.main);
      logger:info("Modem port 'MAIN:"..constants.port.main.."' opened.");
  logger:info("Done.\n");


  
  logger:info("Registering event handlers...");
    event.listen("cluster_data", data_handle);
      logger:info("Listener 'cluster_data' registered.");
  logger:info("Done.\n");



  logger:info("Starting loop...");
    timer_loop = event.timer(1, loop, math.huge); -- start tick loop execution
  logger:info("Done.\n");



  local time_startup_finished = computer.uptime()-time_startup;
  logger:info("Successfully started up in "..(time_startup_finished).." seconds.\n\n");
end

function shutdown() -- Main shutdown function, executed once at shutdown
  local time_shutdown = computer.uptime();
  
  
  logger:info("----- SHUTDOWN -----", false);
  logger:info("Shutting down...\n");



  logger:info("Configuring modem...");
    modem.close(constants.port.main); -- open main port
      logger:info("Modem port 'MAIN:"..constants.port.main.."' closed.\n");
  logger:info("Done.\n");



  logger:info("Unregistering event handlers...");
    event.ignore("cluster_data", data_handle);
      logger:info("Listener 'cluster_data' unregistered.");
  logger:info("Done.\n");



  logger:info("Stopping loop...");
    event.cancel(timer_loop); -- cancel tick loop execution
  logger:info("Done.\n");



  local time_shutdown_finished = computer.uptime()-time_shutdown;
  logger:info("Successfully shut down in "..(time_shutdown_finished).." seconds.");



  logger:close(); -- close logger
  running = false; -- mark execution as not running

  os.exit(0); -- exit
  logger:info("Exiting.");


  -- TODO: tell common node to disconnect?
end
--



startup();
local success, result = thread.waitForAny({thread_interrupt}); -- start all remaining threads and halt
shutdown();