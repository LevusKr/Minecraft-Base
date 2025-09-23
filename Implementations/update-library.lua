--[[
    Update-Library
    This library provides functionality to communicate with the remote Update-Server and the local Update-Daemon.
--]]


-- Files and Configurations
local file_updates = "/etc/updates.cfg"; --- List of updateable files
--

-- Libraries and components
local Config = require("cluster/config");
local constants = require("cluster/constants");
local Packet = require("cluster/network_packet");
local utils = require("cluster/utils");
local utils_file = require("cluster/utils-file");

local component = require("component");
local os = require("os");
local term = require("term");
local event = require("event");


local modem = component.modem;
local data = component.data;
--

-- Data tables
local config_updates = Config:create( file_updates );

local update = {cfg = config_updates};
-- 




--<< API Methods >>--

--- Loads list of updateable files from 'file_updates'
function update.load_local()

    local success_config_updates, result_config_updates = config_updates:load();

    if not success_config_updates then

        return false, result_config_updates;

    elseif type( result_config_updates ) ~= "table" then

        return false, "Updates file '/etc/updates.cfg' is malformed";

    end

    return true, result_config_updates;

end

--- Hashes each file's content for later comparing to remote files at update server
-- TODO: currently this only supports one-level sections, so add truly recursive behavior
function update.hash_local(options)

    local files = {};
    local file_hashes = {};
    local file_hashes_count = 0;

    --- Iterate list of updateable files and generate checksum for each
    for key, entry in pairs( config_updates:content( options ) ) do

        --- If entry is table, it is not a file path but a section containing multiple paths
        if type( entry ) == "table" then

            for _, file in pairs( entry ) do

                files[ #files + 1 ] = key .. file;

            end

        elseif type( entry ) == "string" then

            term.write("string")

            files[ #files + 1 ] = entry;

        end

    end

    
    for _, file in pairs( files ) do

        local file_content = utils_file._read(file, true);

        if file_content then

            file_hashes[ file ] = data.crc32( file_content );

            file_hashes_count = file_hashes_count + 1;

        end

    end



    return true, file_hashes, file_hashes_count;

end

function update.hash(file)

    local file_content = utils_file._read(file, true);
    local file_hashes = {};

    if file_content then

        file_hashes[ file ] = data.crc32( file_content );

        return file_hashes;


    end

end


-- TODO: implement
function update.load_remote()

end

-- TODO: implement
function update.hash_remote()

end



-- Operate at Update-Server with given arguments and return Future object
function update.operate(operation, files, files_count, options)

    options = options or {};


    local packet_request = Packet:create(
        modem.address,
        constants.name.update,
        constants.port.update,
        constants.packet.data,
        {
            operation = operation or "check",
            files = files or {},
            files_count = files_count or 0
        }
    )

    --- Success of sending packet and optional error message
    local success, result = packet_request:send{open_port = true, encrypt = true};

    result = result or "Update-Server unreachable"; --- If no error message is present, use default error message

    if not success then
        return _, success, result;
    end


    local response_future = packet_request:await_response(

        options.async,
        options.timeout

    );

    response_future:on_success(
        function(packet_response)

            --- If response arrived successfully but it contains an error message (e.g. nas-server not reachable)
            if not packet_response.data.success then

                result = packet_response.data.result;
                return;
                
            end


            local updates_available = {};
            local updates_count = 0;

            for response_file, response_data in pairs( packet_response.data.result ) do

                --- If 'response_data' is new file content
                if type( response_data ) == "string" and operation == "download" then

                    cwrite(options.write, "Update for '" .. response_file .. "' downloaded.\n");

                    --- Decompress and write new file content to disk
                    local success_write, result_write = utils_file.write(response_file, data.inflate( response_data ));

                    if success_write then
                        cwrite(options.write, "Update for '" .. response_file .. "' installed.\n\n");

                        updates_count = updates_count + 1;
                    else
                        cwrite(options.write, "Update for '" .. response_file .. "' could not be installed: " .. tostring( result_write ) .. "\n\n");
                    end

                elseif (type( response_data ) == "boolean") and (response_data == false) then --- If 'response_data' is update availability

                    cwrite(options.write, "Update for '" .. response_file .. "' available.\n");
                
                    --- Store file path if update is available, e.g. for later downloading manually
                    updates_available[ #updates_available + 1 ] = response_file;

                end
            end

            cwrite(options.write, tostring( updates_count ) .. " updates installed.\n");
            cwrite(options.write, tostring( #updates_available ) .. " updates available.\n");

            success = true;
            result = "Checked " .. tostring( files_count ) .. " files.";

        end
    ):on_failure(
        function(error)

            success = false;
            result = error or result;

        end
    ):on_completion(
        function()

            response_future.result = {
                success = success,
                result = result
            }

        end
    );


    return response_future, success, result;

end

--- Checks availability of updates for given files
function update.check(files, files_count, options)

    return update.operate(
        "check",
        files,
        files_count,
        options
    );

end

--- Downloads updates for given files
function update.download(files, files_count, options)

    return update.operate(
        "download",
        files,
        files_count,
        options
    );

end

--<< API Methods end >>--

function cwrite(condition, text)

    if condition then

        term.write(text);

    end

end




--- Return API Methods as table
return update;