-- DNS files
local dnsFile = "/etc/dns.cfg";
local reverseDnsFile = "/etc/rdns.cfg";
local logFile = "/var/log/dns-server.log"

-- Libraries and components
local component = require("component");
local filesystem = require("filesystem");
local utils = require("cluster/utils");
local event = require("event");
local term = require("term");

local modem = component.modem;
--



-- DNS entries
dns = {}
reverseDns = {}

-- Functions for manipulating DNS entries
function createDnsEntry(name, address)
  if not dns[string.lower(name)] and not reverseDns[string.lower(address)] then
    dns[string.lower(name)] = string.lower(address);
    reverseDns[string.lower(address)] = string.lower(name);

    return utils.config.save(dnsFile, dns) and utils.config.save(reverseDnsFile, reverseDns);
  end
  return false;
end

function deleteDnsEntry(name)
  local address = dns[string.lower(name)];
  local updated = false;

  if reverseDns[string.lower(address)] then
    reverseDns[string.lower(address)] = nil;
    updated = true;
  end
  if dns[string.lower(name)] then
    dns[string.lower(name)] = nil;
    updated = true;
  end

  return utils.config.save(dnsFile, dns) and utils.config.save(reverseDnsFile, reverseDns) and updated;
end

function deleteReverseDnsEntry(address)
  local name = reverseDns[string.lower(address)];
  local updated = false;

  if dns[string.lower(name)] then
    dns[string.lower(name)] = nil;
    updated = true;
  end
  if reverseDns[string.lower(address)] then
    reverseDns[string.lower(address)] = nil;
    updated = true;
  end

  return utils.config.save(dnsFile, dns) and utils.config.save(reverseDnsFile, reverseDns) and updated;
end
--

-- Functions for querying DNS entries
function lookupDnsEntry(name)
  result, address = pcall(function() return dns[string.lower(name)] end);
  if result then return address else return nil end
end

function lookupReverseDnsEntry(address)
  result, name = pcall(function() return reverseDns[string.lower(address)] end);
  if result then return name else return nil end
end
--



-- Load DNS entries
if filesystem.exists(dnsFile) then
  temp = utils.config.load(dnsFile);
  if temp then
    dns = temp;
  end
else
  --create
end

if filesystem.exists(reverseDnsFile) then
  temp = utils.config.load(reverseDnsFile);
  if temp then
    reverseDns = temp;
  end
else
  --filesystem.create
end

if not filesystem.exists(logFile) then
  temp = utils.config.load(reverseDnsFile);
  if temp then
    reverseDns = temp;
  end
end
--

term.clear();
term.write("DNS Server\n\n");

-- Main loop
while true do
  modem.open(constants.port.dns);

  local event, _, address, _, _, message = event.pull("modem_message");
  status, message = utils.encoding.decode(message);
  if status then
    if message.action == "create" then
      local success = createDnsEntry(message.name, message.address or address);
      if success then
        local _, data = utils.encoding.encode({action = "create", response = message.address or address})
        modem.send(address, constants.port.dns, data);

        utils.logging.info("Successfully created DNS entry '"..message.name..":"..(message.address or address).."'", logFile);
      else
        utils.logging.info("Failed to create DNS entry '"..message.name..":"..(message.address or address).."'", logFile);
      end
    end

    if message.action == "delete" then
      local success = false;
      if message.name then success = deleteDnsEntry(message.name); end
      if message.address then success = deleteReverseDnsEntry(message.address); end

      local _, data = utils.encoding.encode({action = "delete", response = success});
      modem.send(address, constants.port.dns, data);

      if success then
        utils.logging.info("Successfully deleted DNS entry '"..message.name.."'", logFile);
      else
        utils.logging.info("Failed to delete DNS entry '"..(message.name or "N/A")..":"..(message.address or "N/A").."'", logFile);
      end
    end

    if message.action == "lookup" then
      local lookupResponse = lookupDnsEntry(message.name) or nil;

      local _, data = utils.encoding.encode({action = "lookup", response = lookupResponse});
      modem.send(address, constants.port.dns, data);

      utils.logging.info("'"..(lookupReverseDnsEntry(address) or address).."' looked up DNS entry for '"..message.name.."' -> '"..(lookupResponse or "N/A").."'", logFile);
    end

    if message.action == "rlookup" then
      local lookupResponse = lookupReverseDnsEntry(message.address) or nil;

      local _, data = utils.encoding.encode({action = "rlookup", response = lookupResponse});
      modem.send(address, constants.port.dns, data);

      utils.logging.info("'"..(lookupReverseDnsEntry(address) or address).."' looked up reverse DNS entry for '"..message.address.."' -> '"..(lookupResponse or "N/A").."'", logFile);
    end
  end
end
