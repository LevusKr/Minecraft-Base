-- Libraries and components
local component = require("component")
local serial = require("serialization")
local event = require("event")
local utils = require("cluster/utils")

local modem = component.modem
--


-- Function table
local dns = {}

-- Create DNS entry with given name and address, or local modem address if address is nil
function dns.createDnsEntry(_name, _address)
  modem.open(constants.port.dns)
  modem.broadcast(constants.port.dns, serial.serialize({action = "create", name = _name, address = _address}))

  return dns.awaitResponse()
end

-- Delete DNS entry with given name, or local modem name if name is nil
function dns.deleteDnsEntry(_name)
  modem.open(constants.port.dns)
  modem.broadcast(constants.port.dns, serial.serialize({action = "delete", name = _name}))

  return dns.awaitResponse()
end

-- Delete DNS entry with given address, or local modem address if address is nil
function dns.deleteReverseDnsEntry(_address)
  modem.open(constants.port.dns)
  modem.broadcast(constants.port.dns, serial.serialize({action = "delete", address = _address}))

  return dns.awaitResponse()
end

-- Query DNS server for address by given name
function dns.lookup(_name)
  modem.open(constants.port.dns)
  modem.broadcast(constants.port.dns, serial.serialize({action = "lookup", name = _name}))

  return dns.awaitResponse()
end

-- Query DNS server for name by given address
function dns.reverseLookup(_address)
  modem.open(constants.port.dns)
  modem.broadcast(constants.port.dns, serial.serialize({action = "rlookup", address = _address}))

  return dns.awaitResponse()
end

-- Await response to querying
function dns.awaitResponse(timeout)
  local success = false
  local result = nil

  modem.open(constants.port.dns)  
  local event, _, address, _, _, message = event.pull((timeout or 5), "modem_message")
  modem.close(constants.port.dns)

  if event then
    status, message = pcall(serial.unserialize, message)
    if status then
      result = message.response
      if message.response then
        success = true
      end
    end
  end

  return success, result
end


-- Return table with functions
return dns
