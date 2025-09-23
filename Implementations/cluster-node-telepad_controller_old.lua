--[[
    Telepad-Display
    Telepad-Display component of network cluster structure
    A Telepad-Display acts as manager of a single adjacent telepad, thus allowing to control it, e.g. choosing teleport destination
    and receiving (and displaying) general information, e.g. current address, destination address, connection status etc.
--]]


-- Files and Configurations
local file_log = "/var/log/cluster/node-%s.log"; -- TODO: create new file at every startup?
local file_telepads = "/etc/telepads.cfg"; -- effectively a register for various target addresses, collerated with a display name (dns-like)   TODO: add to /etc/update.cfg so this isn't purely local
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
local gpu = component.gpu; -- primary gpu
local telepad = component.telepad; -- primary telepad
--

-- Variables and constants
local logger = nil;
local log_print = true;
local log_debug = true;
local log_buffer = true; -- whether buffer logs or not

local hostname = nil;

local timer_loop = 0; -- timer id of main loop


local refresh_time = 0.5; -- update interval (refresh rate) [seconds/update]

local res_x, res_y = gpu.getResolution(); -- current (or default) gpu resolution
local x, y = 2, 2; -- position of drawing container
local width, height = res_x - 2*x - 1, res_y - 2*y - 1; -- width and height of drawing container (here: fullscreen but with x and y margin -> correct x,y; add margin x,y; -> 2*x,y)
local color_success, color_failure, color_background, color_foreground = 0x00B600, 0xFF0000, 0x000000, 0xFFFFFF; -- graphs and background color

local telepads_register = {}; -- data table storing address-name-pairs ({"Destination_1"=*telepad address*}, ...)
local telepads_register_count = 0; -- TODO: avoid
local telepad_data = {}; -- data table storing current data, gathered in display_loop, for using in display_draw (e.g. destination, validity, ...)
--



-- Receives internal data from Core, passed through by Node via cluster_data event
function data_handle(_, data) -- receives commands from global telepad controller
  local packet = select(2, utils.encoding.decode(data))
  if packet.port ~= constants.port.main then return; end


  local action = packet.data.action; -- what to perform on telepad (e.g. change target)
  local payload = packet.data.payload; -- data for manipulating (e.g. target address)
  local response = {}; -- to-be-responded data

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


-- Node Functions --
function display_setup()
  telepads_register = setmetatable(utils.internal.custom(file_telepads), { -- load telepad address-name-pairs, metatable for address-name query
    __index = function(self, key)
      local i = 1;
      for name, address in pairs(self) do
        if key == address then
          return name;
        elseif key == i then
          return tonumber(address)
        end

        i = i+1;
      end
    end
  });

  for _, _ in pairs(telepads_register) do
    telepads_register_count = telepads_register_count+1;
  end

  term.clear();
end

function display_draw() -- draw telepad information and list of available targets (from file_telepads) to choose from or accept manual address input
  gpu.fill(1, 1, width, 1, " ");
  gpu.fill(1, 1+1, width, 1, " ");

  --(telepad_data.name_local or telepad_data.address_local); -- current set local address/name if available
  --(telepad_data.name_target or telepad_data.address_target); -- current set target address/name if available
  --telepad_data.status_target; -- whether teleport with current config is possible
  --telepad_data.status_target_message; -- additional message for teleport status (SUCCESS, TARGET_NOT_FOUND, TARGET_DISABLED)
  local label_local = telepad_data.name_local or telepad_data.address_local;
  local label_target = " → "..(telepad_data.name_target or telepad_data.address_target);

  gpu.set(1, 1, label_local);

  gpu.set(1, 1+1, label_target);

  gpu.setForeground(telepad_data.status_target and color_success or color_failure);
  gpu.set(label_target:len(), 1+1, "● "..telepad_data.status_target_message);

  gpu.setForeground(color_foreground);


  local index = 4;
  for name, address in pairs(telepads_register) do -- iterate over known targets and provide list ui to choose target
    local list_label = name.." → "..address;
    gpu.set(3, index, list_label);


    index = index+1;
  end
end

function display_loop()
  local address_local = tostring(telepad.getAddress());
  local name_local = telepads_register[address_local]; -- TODO: should the local name even change? like you won't randomly change a local address to a already registered one manually, if you do, shut this down before
  local status_local = telepad.isAddressValid();

  local address_target = tostring(telepad.getTargetAddress());
  local name_target = telepads_register[address_target];
  local status_target, status_target_message = telepad.getTargetStatus();

  telepad_data = {
    address_local = address_local,
    name_local = name_local,
    status_local = status_local,
    address_target = address_target,
    name_target = name_target,
    status_target = status_target,
    status_target_message = status_target_message
  };

  display_draw();
end

function display_touch(_, _, x, y)
  if (y >= 4) and (y <= telepads_register_count+4) then -- area of target list
    index = y-3;
    address = telepads_register[index];

    telepad.setTargetAddress(address);
  end
end
--


-- Main Functions --
function loop() -- Main loop function, executed once every second
  display_loop();
end

function startup() -- Main startup function, executed once at startup
  local time_startup = computer.uptime();

  running = true; -- mark execution as running
  hostname = utils.internal.hostname(); -- read hostname from /etc/hostname
  file_log = file_log:format(hostname); -- set log file to hostname (multiple instances possible, so not differ by node-telepad_controller, but node-telepad_controller-01, ...)
  logger = utils.logging.logger(hostname, file_log, log_print, log_debug, log_buffer);

  
  term.clear(); -- clear previous stuff
  logger:info("----- STARTUP -----", false);
  logger:info("Starting up...\n");
  
  

  logger:info("Checking if node is connected to core...");
    -- check wether common node daemon is connected to the core   TODO: shutdown etc.
    if not os.getenv(constants.env.connected) then shutdown(); end -- if not connected print error and shutdown gracefully
  logger:info("Done.\n");
  
  

  logger:info("Configuring modem...");
    modem.open(constants.port.main);
      logger:info("Modem port 'MAIN:"..constants.port.main.."' opened.");
  logger:info("Done.\n");


  
  logger:info("Registering event handlers...");
    event.listen("cluster_data", data_handle);
      logger:info("Listener 'cluster_data' registered.");
    event.listen("touch", display_touch);
      logger:info("Listener 'touch' registered.");
  logger:info("Done.\n");



  logger:info("Starting loop...");
    timer_loop = event.timer(refresh_time, loop, math.huge); -- start tick loop execution
  logger:info("Done.\n");



  local time_startup_finished = computer.uptime()-time_startup;
  logger:info("Successfully started up in "..(time_startup_finished).." seconds.\n\n");



  display_setup();
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
    event.ignore("touch", display_touch);
      logger:info("Listener 'touch' unregistered.");
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