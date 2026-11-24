--[[
    NAS-Daemon (Virtual-Filesystem)
    This daemon provides functionality for emulating a mounted filesystem
    and relaying method calls to the NAS-Server.
--]]


-- Libraries and components
local Cache = require("cluster/cache");
local nas = require("cluster/nas-library");

local component = require("component");
local computer = require("computer");
local event = require("event");
local filesystem = require("filesystem");
local package = require("package");
--

-- Data tables
local component_original = {}; --- Copy of component api to still being able to use them in modifed methods
local component_modified = {}; --- Component api injected with modified functions

--- Virtual filesystem component to emulate a OpenComputers component   TODO: (random?) generate address; is setting slot as '-1' valid? 
local filesystem_virtual = {
    slot = -1,
    address = "76e3d704-07d4-4c30-9f74-d58f3ff278e4",
    componentType = "filesystem",
};


--- This cache holds various file attributes from bulk nas#info requests (see 'nas.info')
--- 5 minutes cache interval
local cache_file_attributes = Cache.create(
    function(path)

        local _, success, result = nas.info( path );

        if not success then

            event.onError( tostring( result ) );

            return nil;

        end

        return result;

    end,
    
    2*60 --- 2 Minutes cache life
);
---
--



filesystem_virtual.getLabel = function()

    return "NAS";

end

--- Disable changing label to something else than what this virtually describes (a NAS)
filesystem_virtual.setLabel = function()

    return "NAS";

end

filesystem_virtual.isReadOnly = function()

    return false;

end

filesystem_virtual.spaceUsed = function()

    local _, success, result = nas.space_used();

    if not success then

        return -1;

    end

    return result;

end

filesystem_virtual.spaceTotal = function()

    local _, success, result = nas.space_total();

    if not success then

        return -1;

    end

    return result;

end

filesystem_virtual.size = function(path)

    local success, result = false, -1;


    local cache_success, cached_attributes = cache_file_attributes:get( path );

    --- Try to retrieve attribute from cache, otherwise execute single request
    if cache_success and cached_attributes and cached_attributes.size and cached_attributes.size.success then

        success = true;
        result = cached_attributes.size.result;

    else

        _, success, result = nas.size( path );

    end


    return
        success
        and result
        or -1
    ;

end

filesystem_virtual.exists = function(path)

    local success = false;


    local cache_success, cached_attributes = cache_file_attributes:get( path );

    --- Try to retrieve attribute from cache, otherwise execute single request
    if cache_success and cached_attributes and cached_attributes.exists then

        success = cached_attributes.exists.success;

    else

        _, success = nas.exists( path );

    end


    return success;

end

filesystem_virtual.lastModified = function(path)

    local success, result = false, -1;


    local cache_success, cached_attributes = cache_file_attributes:get( path );

    --- Try to retrieve attribute from cache, otherwise execute single request
    if cache_success and cached_attributes and cached_attributes.last_modified and cached_attributes.last_modified.success then

        result = cached_attributes.last_modified.result;

    else

        _, success, result = nas.last_modified( path );

    end


    return
        success
        and result
        or -1
    ;

end

filesystem_virtual.isDirectory = function(path)

    local success = false;


    local cache_success, cached_attributes = cache_file_attributes:get( path );

    --- Try to retrieve attribute from cache, otherwise execute single request
    if cache_success and cached_attributes and cached_attributes.is_directory then

        success = cached_attributes.is_directory.success;

    else

        _, success = nas.is_directory( path );

    end


    return success;

end

filesystem_virtual.list = function(path)

    local _, success, result = nas.list( path );

    if not success then

        return { tostring( result ) };

    end

    return result;

end

filesystem_virtual.makeDirectory = function(path)

    return true;

end

filesystem_virtual.rename = function(oldPath, newPath)

    return true;

end

filesystem_virtual.remove = function(path)

    local _, success, result = nas.remove( path );

    return success, result;

end

filesystem_virtual.open = function(path, mode)

    local modes = {
        r = "r",
        w = "w",
        a = "a",
        rb = "rb",
        wb = "wb",
        ab = "ab"
    }

    if not modes[ mode ] then

        return nil, "unsupported mode";

    end


    local _, success, result = nas.open(path, mode);

    if not success then

        return nil;

    end


    return {
        path = path,
        mode
    };

end

filesystem_virtual.write = function(handle, value)

    handle = handle or {};

    local _, success, result = nas.write(handle.path, value, true);

    if not success then

        return false;

    end

    return result;

end

filesystem_virtual.read = function(handle, count)

    handle = handle or {};

    local _, success, result = nas.read(handle.path, count, true);

    if not success then

        return nil;

    end

    return result;

end

filesystem_virtual.seek = function(handle, whence, offset)

    return "testseekeddata";

end

filesystem_virtual.close = function(handle)

    handle = handle or {};

    local _, success, result = nas.close( handle.path );

    return success, result;

end




component_modified.proxy = function(address)

    if address == filesystem_virtual.address then

        return filesystem_virtual;

    else

        return component_original.proxy( address );

    end

end

component_modified.list = function(filter, exact)

    local list = component_original.list(filter, exact);

    if not filter or (filter == "filesystem") then

        list[ filesystem_virtual.address ] = "filesystem";

    end


    return list;

end


function start()

    for name, func in pairs( component_modified ) do

        --- Transfer original functions
        component_original[ name ] = component[ name ];
    
        --- Overwrite functions
        component[ name ] = func;
    
    end

    computer.pushSignal("component_added", filesystem_virtual.address, "filesystem");

    filesystem.mount(filesystem.proxy(filesystem_virtual.address), "/nas");

end

function stop()

    --- To remove spoofed functions and reset to normal, just force reload the original library from disk
    package.loaded.component = nil;
    component = require("component");

    computer.pushSignal("component_removed", filesystem_virtual.address, "filesystem");

end