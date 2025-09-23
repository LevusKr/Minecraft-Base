--[[
    Switch
    Switch component of network cluster structure
    A Switch acts as repeater and connector for networks, thus connecting network components
    and sending network packets either by just repeating, or optionally filtering and routing them.
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-implementation"; -- TODO: create new file at every startup?
--

-- Libraries and components
local component = require("component");

local modem = component.proxy(component.list("modem")()); -- primary modem
local modems = {}; -- all modems
--

-- Variables and constants
local logger = nil;
local log_print = true;
local log_debug = true;

local timer_loop = 0; -- timer id of main loop
--



-- Receives internal data from Core, passed through by Node via cluster_data event
function data_handle(_, data)
  
end

-- Send internal data to Core, passed through by Node via internal_data event
function data_send(data)
  event.push("internal_data", data); -- TODO: data size and type etc.
end



-- Thread for handling program interruption
local thread_interrupt = thread.create(
  function()
    print("before interrupted")
    event.pull("interrupted"); -- wait until interrupt event
    print("after interrupted")
    running = false; -- mark execution as not running
  end
);


-- Continously repeated function for refreshing display etc.
local function tick()
end

-- Function getting called once at startup
function startup()
  local time_startup = computer.uptime();

  running = true; -- mark execution as running
  logger = utils.logging.logger(file_log, true); -- TODO: declare variable for print enabling



  logger:info("----- STARTUP -----", false);
  logger:info("Successfully prepared logger.", false);
  logger:info("Starting up...\n");
  
  
  -- check wether common node daemon is connected to the core
  if not os.getenv(constants.env.connected) then shutdown(); end -- if not connected print error and shutdown gracefully
  
  
  modem.open(constants.port.main);
  logger:info("Modem port 'MAIN:"..constants.port.main.."' opened.\n");

  
  event.listen("cluster_data", data_handle);
  timer_loop = event.timer(1, tick, math.huge); -- start tick loop execution
end

-- Function getting called once at shutdown   TODO: logs
function shutdown()
  --utils.logging.info("Shutting down...", log_local);  
  
  modem.close(constants.port.remote);
  
  event.ignore("cluster_data", data_handle);
  event.cancel(timer_loop); -- stop tick loop execution
end



startup();
local success, result = thread.waitForAny({thread_interrupt}); -- start all remaining threads and halt
shutdown();