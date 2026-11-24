--[[
    Update-Library
    This library provides functionality to communicate with the remote Update-Server, NAS-Server and the local Update-Daemon.
--]]


-- Files and Configurations
local file_updates = "/etc/updates.cfg"; --- List of updateable files
--

-- Libraries and components
local codec = require("cluster/codec");
local Config = require("cluster/config");
local constants = require("cluster/constants");
local Future = require("cluster/future");
local nas = require("cluster/nas-library");
local Packet = require("cluster/network_packet");
local utils = require("cluster/utils");
local utils_file = require("cluster/utils-file");
local utils_string = require("cluster/utils-string");

local component = require("component");
local computer = require("computer");
local filesystem = require("filesystem");
local os = require("os");


local modem = component.modem;
local data = component.isAvailable("data") and component.data or nil;
local cwrite = utils_string.cwrite;
--

-- Variables and Constants
local delta_size_min = 256;   --- Minimum file byte size for which chunk-level delta encoding is attempted
local timeout_default = 10;   --- Default request timeout in seconds
--

-- Data tables
local config_updates = Config:create( file_updates );

local update = {
    cfg         = config_updates,
    available   = {},
    last_result = nil
};
--




--<< Helper Functions >>--

--- Enriches a plain { [file] = hash } table with local chunk hashes for delta downloads on demand
local function attach_delta_chunks(files, force)

    if force or type( files ) ~= "table" then
        return files;
    end


    local enriched = {};

    for entry_file, entry_info in pairs( files ) do

        if type( entry_info ) == "string" then

            local content = utils_file._read(entry_file, true);

            if content and #content >= delta_size_min then

                local chunks = utils_file.chunk( content );

                enriched[ entry_file ] = {
                    hash   = entry_info,
                    chunks = utils_file.hash_chunks( chunks )
                };

            else

                enriched[ entry_file ] = entry_info;

            end

        else

            enriched[ entry_file ] = entry_info;

        end

    end


    return enriched;

end

--- Safe string trim helper (falls back to pattern match if local utils-string has not been updated yet)
local function trim_string(str)

    if str == nil then
        return "";
    end

    if utils_string.trim then
        return utils_string.trim( str );
    end

    return tostring( str ):match("^%s*(.-)%s*$") or "";

end

--- Normalizes a single file path or list of file paths into a sorted array of absolute paths
local function normalize_target_files(input)

    local list = (type( input ) == "table") and input or { input };
    local files = {};
    local seen = {};

    for _, entry in ipairs( list ) do

        if type( entry ) == "string" and entry ~= "" then

            for part in entry:gmatch("([^,]+)") do

                local trimmed = trim_string( part );

                if trimmed ~= "" then

                    local normalized = utils_file.join_path("", trimmed);

                    --- Convenience: just like OpenOS shell, if '.lua' was omitted and the '.lua' file exists locally, resolve it
                    if not filesystem.exists( normalized ) and not normalized:match("%.[%w_]+$") and filesystem.exists( normalized .. ".lua" ) then
                        normalized = normalized .. ".lua";
                    end

                    if not seen[ normalized ] then

                        seen[ normalized ] = true;
                        files[ #files + 1 ] = normalized;

                    end

                end

            end

        end

    end

    table.sort( files );

    return files;

end

---<< Helper Functions end >>--




--<< API Methods >>--

--- Loads list of updateable files from 'file_updates'
function update.load_local()

    local success_config_updates, result_config_updates = config_updates:load();

    if not success_config_updates then

        return false, result_config_updates;

    elseif type( result_config_updates ) ~= "table" then

        return false, "Updates file '" .. file_updates .. "' is malformed";

    end

    return true, result_config_updates;

end

--- Recursively resolves all updateable file paths from '/etc/updates.cfg' (or explicit target files)
function update.list_local(options)

    options = options or {};


    --- If explicit target file(s) were specified, resolve them directly without requiring '/etc/updates.cfg'
    if options.files or options.file then

        local explicit_files = normalize_target_files(options.files or options.file);
        return true, explicit_files, #explicit_files;

    end


    if options.reload or not config_updates.contents or next( config_updates.contents ) == nil then

        local success_load, result_load = update.load_local();

        if not success_load then

            --- If '/etc/updates.cfg' is missing/unreadable but explicit file paths were passed via filter, fall back to those paths
            if options.filter then

                local fallback_files = normalize_target_files( options.filter );

                if #fallback_files > 0 then

                    return true, fallback_files, #fallback_files;

                end

            end

            return false, result_load, 0;

        end

    end


    local success_tree, files, count = utils_file.resolve_tree(config_updates:content(), options.filter);

    if not success_tree then

        return false, files, 0;

    end


    --- If a filter entry is an explicit file path (contains '/' or exists locally) not yet in '/etc/updates.cfg', include it directly
    if options.filter then

        local seen = {};

        for _, f in ipairs( files ) do
            seen[ f ] = true;
        end

        local filter_list = (type( options.filter ) == "table") and options.filter or { options.filter };

        for _, raw_pattern in ipairs( filter_list ) do

            if type( raw_pattern ) == "string" then

                for pattern in raw_pattern:gmatch("([^,]+)") do

                    pattern = trim_string( pattern );

                    local normalized = utils_file.join_path("", pattern);

                    if not filesystem.exists( normalized ) and not normalized:match("%.[%w_]+$") and filesystem.exists( normalized .. ".lua" ) then
                        normalized = normalized .. ".lua";
                    end

                    if not seen[ normalized ] and (pattern:find("/", 1, true) or filesystem.exists( normalized )) then

                        seen[ normalized ] = true;
                        files[ #files + 1 ] = normalized;

                    end

                end

            end

        end

        table.sort( files );
        count = #files;

    end


    return true, files, count;

end

--- Hashes each file's content for later comparing to remote files at update server
function update.hash_local(options)

    options = options or {};


    local success_list, files_or_err = update.list_local( options );

    if not success_list then
        return false, files_or_err, 0;
    end


    local file_hashes = {};
    local file_hashes_count = 0;

    for _, file in ipairs( files_or_err ) do

        if options.force then

            file_hashes[ file ] = false;

        else

            local hash, content = update.hash_local_single(file, options.delta);

            if options.delta and hash and content and #content >= delta_size_min then

                local chunks = utils_file.chunk( content );

                file_hashes[ file ] = {
                    hash   = hash,
                    chunks = utils_file.hash_chunks( chunks )
                };

            else

                --- Use 'false' if local file does not exist so the key remains present in 'file_hashes' table
                file_hashes[ file ] = hash or false;

            end

        end

        file_hashes_count = file_hashes_count + 1;

    end


    return true, file_hashes, file_hashes_count;

end

--- Computes CRC32 checksum for a single local file. Optionally returns the raw file content as second return value
function update.hash_local_single(file, with_content)

    local hash, content = utils_file.hash(file, false);

    if hash then

        if with_content then
            return hash, content;
        end

        return hash;

    end

    return nil, nil;

end

--- Loads remote '/etc/updates.cfg' from NAS-Server
function update.load_remote(options)

    options = options or {};


    local response_future, success, result = nas.read(
        file_updates,
        "*a",
        false,
        options.async,
        options.timeout or timeout_default
    );

    if not options.async then

        if not success or not result then
            return false, result or "Failed to load remote updates configuration";
        end

        local decoded = codec.decode( result );

        if type( decoded ) ~= "table" then
            return false, "Remote updates configuration is malformed";
        end

        return true, decoded;

    end


    return response_future, success, result;

end

--- Retrieves remote CRC32 hashes from NAS-Server for given files (or all locally configured files)
function update.hash_remote(files, options)

    options = options or {};


    if not files then

        local success_local, local_hashes = update.hash_local({reload = true});

        if not success_local then
            return nil, false, local_hashes;
        end

        files = local_hashes;

    end


    return nas.hash(
        files,
        options.async,
        options.timeout or timeout_default
    );

end

--- Syncs local '/etc/updates.cfg' from NAS-Server
function update.sync_config(options)

    options = options or {};


    cwrite(options.write, "Syncing '" .. file_updates .. "' from NAS-Server...\n");

    local success_remote, result_remote = update.load_remote({
        async   = false,
        timeout = options.timeout or timeout_default
    });

    if not success_remote then

        cwrite(options.write, "Error: " .. tostring( result_remote ) .. "\n", io.stderr);
        return false, result_remote;

    end

    local success_write, result_write = utils_file.write(file_updates, codec.encode( result_remote ));

    if not success_write then

        cwrite(options.write, "Error writing '" .. file_updates .. "': " .. tostring( result_write ) .. "\n", io.stderr);
        return false, result_write;

    end

    cwrite(options.write, "Successfully updated '" .. file_updates .. "'.\n");


    return true, result_remote;

end

--- Operate at Update-Server (or directly at NAS-Server) with given arguments and return Future object
function update.operate(operation, files, files_count, options)

    --- Allow shorthand call: update.operate(operation, options)
    if type( files ) == "table" and files_count == nil and options == nil and (files.download ~= nil or files.async ~= nil or files.timeout ~= nil or files.write ~= nil or files.direct ~= nil or files.delta ~= nil or files.force ~= nil or files.filter ~= nil or files.file ~= nil or files.files ~= nil or files.bypass_server ~= nil) then

        options = files;
        files = nil;

    elseif (type( files ) == "string" or (type( files ) == "table" and type( files[1] ) == "string")) and (options == nil and (files_count == nil or type( files_count ) == "table")) then

        --- Allow shorthand call with single path or path array: update.operate(operation, "/path/file.lua", [options])
        options = type( files_count ) == "table" and files_count or {};
        options.files = files;
        files = nil;
        files_count = nil;

    end

    options = options or {};
    operation = operation or "check";

    local use_direct = (options.direct == nil) and true or options.direct;
    local use_delta = (options.delta == nil) and true or options.delta;
    local use_force = options.force or false;
    local timeout = tonumber( options.timeout ) or timeout_default;


    --- If no files table was provided for check/download, automatically hash local files
    if not files and (operation == "check" or operation == "download") then

        local is_targeted = (options.files ~= nil or options.file ~= nil or options.filter ~= nil);
        cwrite(options.write, "Checking local files" .. (is_targeted and " (filtered)" or "") .. "...\n");

        local success_hash, local_hashes, local_count = update.hash_local({
            reload = true,
            delta  = (operation == "download") and use_delta,
            force  = use_force,
            filter = options.filter,
            file   = options.file,
            files  = options.files
        });

        if not success_hash then

            cwrite(options.write, "Error while hashing local files: " .. tostring( local_hashes ) .. "\n", io.stderr);

            local failed_future = Future:create(function() return false, local_hashes; end):run( false );
            failed_future.result = {
                success = false,
                result  = local_hashes
            };

            update.last_result = failed_future.result;

            return failed_future, false, local_hashes;

        elseif local_count == 0 then

            local msg = "No matching files to update-check.";
            cwrite(options.write, msg .. "\n");

            local empty_future = Future:create(function() return true, msg; end):run( false );
            empty_future.result = {
                success           = true,
                result            = msg,
                checked_count     = 0,
                up_to_date_count  = 0,
                updates_count     = 0,
                updates_available = {},
                updates_installed = {}
            };

            update.last_result = empty_future.result;

            return empty_future, true, msg;

        end

        files = local_hashes;
        files_count = local_count;

    else

        --- Normalize legacy array format {{file = ..., hash = ...}} if passed by an external caller
        if type( files ) == "table" and files[1] and type( files[1] ) == "table" and files[1].file then

            local normalized = {};
            local count = 0;

            for _, item in ipairs( files ) do

                normalized[ item.file ] = (not use_force and item.hash) or false;
                count = count + 1;

            end

            files = normalized;
            files_count = count;

        end

        --- Count files if files_count was not supplied or was 0 while files table is non-empty
        if type( files ) == "table" and (not files_count or files_count == 0) then

            local count = 0;

            for _ in pairs( files ) do
                count = count + 1;
            end

            files_count = count;

        end

        --- If downloading with delta enabled and plain hash strings were passed, attach local chunk hashes
        if operation == "download" and use_delta and not use_force and type( files ) == "table" then

            files = attach_delta_chunks(files, use_force);

        end

    end


    if operation == "check" or operation == "download" then

        local target_label = options.bypass_server and "NAS-Server (direct)" or ("Update-Server" .. (operation == "download" and use_direct and " (direct NAS transfer)" or ""));
        cwrite(options.write, "Contacting " .. target_label .. " with " .. tostring( files_count ) .. " files... (timeout: " .. tostring( timeout ) .. "s)\n\n");

    end


    local receiver = options.bypass_server and constants.name.nas or constants.name.update;
    local port = options.bypass_server and constants.port.file or constants.port.update;

    local payload = nil;

    if options.bypass_server then

        payload = {
            operation = "compare",
            file      = files or {},
            options   = {
                download   = (operation == "download"),
                delta      = use_delta,
                force      = use_force,
                invalidate = (operation == "invalidate")
            }
        };

    else

        payload = {
            operation   = operation,
            files       = files or {},
            files_count = files_count or 0,
            options     = {
                direct  = use_direct,
                delta   = use_delta,
                force   = use_force,
                timeout = timeout
            }
        };

    end


    local packet_request = Packet.create(
        modem.address,
        receiver,
        port,
        constants.packet.data,
        payload
    );

    --- Success of sending packet and optional error message
    local success, result = packet_request:send{open_port = true, encrypt = true};

    result = result or (options.bypass_server and "NAS-Server unreachable" or "Update-Server unreachable"); --- If no error message is present, use default error message

    if not success then

        cwrite(options.write, "Error: " .. tostring( result ) .. "\n", io.stderr);

        local failed_future = Future:create(function() return false, result; end):run( false );
        failed_future.result = {
            success = false,
            result  = result
        };

        update.last_result = failed_future.result;

        return failed_future, false, result;

    end


    local response_future = packet_request:await_response(
        options.async,
        timeout
    );

    local details = {
        checked_count     = files_count or 0,
        up_to_date_count  = 0,
        updates_count     = 0,
        delta_count       = 0,
        full_count        = 0,
        failed_count      = 0,
        updates_available = {},
        updates_installed = {},
        bytes_transferred = 0,
        bytes_saved       = 0,
        direct            = false
    };

    response_future:on_success(
        function(packet_response)

            --- If response arrived successfully but it contains an error message (e.g. nas-server not reachable)
            if not packet_response.data or not packet_response.data.success then

                success = false;
                result = (packet_response.data and packet_response.data.result) or "Unknown error from server";
                return;

            end


            details.direct = packet_response.data.direct == true;

            --- Handle non-file operations such as 'invalidate' or 'stats'
            if operation ~= "check" and operation ~= "download" then

                success = true;
                result = packet_response.data.result;
                return;

            end


            local response_map = packet_response.data.result;

            if type( response_map ) ~= "table" then

                success = true;
                result = tostring( response_map );
                return;

            end


            --- Report any requested files that did not exist on the remote server
            if type( files ) == "table" then

                local requested_sorted = {};

                for req_file in pairs( files ) do
                    if response_map[ req_file ] == nil and response_map[ req_file .. ".lua" ] == nil then
                        requested_sorted[ #requested_sorted + 1 ] = req_file;
                    end
                end

                table.sort( requested_sorted );

                for _, missing_file in ipairs( requested_sorted ) do

                    details.failed_count = details.failed_count + 1;
                    cwrite(options.write, "Remote file '" .. missing_file .. "' not found on server.\n", io.stderr);

                end

            end


            --- Sort file keys alphabetically for clean, deterministic terminal output
            local sorted_files = {};

            for response_file in pairs( response_map ) do
                sorted_files[ #sorted_files + 1 ] = response_file;
            end

            table.sort( sorted_files );


            for _, response_file in ipairs( sorted_files ) do

                local response_data = response_map[ response_file ];

                if response_data == true then

                    details.up_to_date_count = details.up_to_date_count + 1;
                    cwrite(options.write and options.verbose, "Up-to-date: '" .. response_file .. "'\n");

                elseif operation == "check" and response_data == false then

                    cwrite(options.write, "Update for '" .. response_file .. "' available.\n");

                    details.updates_available[ #details.updates_available + 1 ] = response_file;

                elseif operation == "download" and (type( response_data ) == "table" or type( response_data ) == "string") then

                    local content_new = nil;
                    local is_delta = false;
                    local saved_bytes = 0;
                    local expected_hash = nil;

                    if type( response_data ) == "table" then

                        expected_hash = response_data.hash;

                        if response_data.delta then

                            is_delta = true;
                            saved_bytes = response_data.saved or 0;

                            local delta_ok, reconstructed = utils_file.apply_delta(response_file, response_data.ops);

                            if delta_ok and (not expected_hash or data.crc32( reconstructed ) == expected_hash) then

                                content_new = reconstructed;

                            else

                                cwrite(options.write and options.verbose, "Delta verification failed for '" .. response_file .. "', fetching full file from NAS...\n");

                                local _, fallback_ok, fallback_content = nas.read(response_file, "*a", false, false, timeout);

                                if fallback_ok and fallback_content then

                                    content_new = fallback_content;
                                    is_delta = false;
                                    saved_bytes = 0;

                                end

                            end

                        elseif type( response_data.content ) == "string" then

                            content_new =
                                response_data.compressed
                                and data.inflate( response_data.content )
                                or response_data.content
                            ;

                        end

                    elseif type( response_data ) == "string" then

                        --- Backwards-compatible support for raw or deflated string responses
                        content_new = response_data;

                        if files and files[ response_file ] and data then
                            local inflated_ok, inflated = pcall(data.inflate, response_data);
                            if inflated_ok and inflated and #inflated > 0 then
                                content_new = inflated;
                            end
                        end

                    end


                    if content_new ~= nil then

                        local mode_label = is_delta and ("delta, saved " .. utils.math.adjust_value(saved_bytes, "B")) or ("full, " .. utils.math.adjust_value(#content_new, "B"));
                        cwrite(options.write, "Update for '" .. response_file .. "' downloaded (" .. mode_label .. ").\n");

                        local success_write, result_write = utils_file.write(response_file, content_new, {binary = true});

                        if success_write then

                            cwrite(options.write, "Update for '" .. response_file .. "' installed.\n");

                            details.updates_count = details.updates_count + 1;
                            details.updates_installed[ #details.updates_installed + 1 ] = response_file;
                            details.bytes_transferred = details.bytes_transferred + math.max(0, #content_new - saved_bytes);
                            details.bytes_saved = details.bytes_saved + saved_bytes;

                            if is_delta then
                                details.delta_count = details.delta_count + 1;
                            else
                                details.full_count = details.full_count + 1;
                            end

                        else

                            details.failed_count = details.failed_count + 1;
                            cwrite(options.write, "Update for '" .. response_file .. "' could not be installed: " .. tostring( result_write ) .. "\n", io.stderr);

                        end

                    else

                        details.failed_count = details.failed_count + 1;
                        cwrite(options.write, "Update for '" .. response_file .. "' failed to decode.\n", io.stderr);

                    end

                end

            end


            if operation == "check" then

                update.available = details.updates_available;

                cwrite(options.write, tostring( #details.updates_available ) .. " updates available (" .. tostring( details.up_to_date_count ) .. "/" .. tostring( details.checked_count ) .. " up-to-date).\n");

                success = true;
                result = "Checked " .. tostring( details.checked_count ) .. " files (" .. tostring( #details.updates_available ) .. " updates available).";

            elseif operation == "download" then

                update.available = {};

                local transfer_note = details.direct and " via direct NAS transfer" or "";
                local delta_note = (details.delta_count > 0) and (" (" .. tostring( details.delta_count ) .. " delta, saved " .. utils.math.adjust_value(details.bytes_saved, "B") .. ")") or "";

                cwrite(options.write, tostring( details.updates_count ) .. " updates installed" .. delta_note .. transfer_note .. ".\n");

                success = details.failed_count == 0;
                result = "Checked " .. tostring( details.checked_count ) .. " files, installed " .. tostring( details.updates_count ) .. " updates" .. delta_note .. ".";

            end

        end
    ):on_failure(
        function(error)

            success = false;
            result = error or result;

        end
    ):on_completion(
        function()

            details.success = success;
            details.result = result;

            response_future.result = details;
            update.last_result = details;

            if operation == "download" and options.reboot and success and (details.updates_count or 0) > 0 then

                cwrite(options.write, "Rebooting to apply installed updates...\n");
                os.sleep( 1 );
                computer.shutdown( true );

            end

        end
    );


    return response_future, success, result;

end

--- Checks availability of updates for given files (or all local files if 'files' is omitted)
function update.check(files, files_count, options)

    return update.operate(
        "check",
        files,
        files_count,
        options
    );

end

--- Downloads updates for given files (or all local files if 'files' is omitted)
function update.download(files, files_count, options)

    return update.operate(
        "download",
        files,
        files_count,
        options
    );

end

--- Downloads updates directly from NAS-Server, bypassing Update-Server
function update.download_direct(files, files_count, options)

    options = options or {};
    options.bypass_server = true;

    return update.operate(
        "download",
        files,
        files_count,
        options
    );

end

--- Requests cache invalidation on Update-Server and NAS-Server
function update.invalidate(options)

    return update.operate(
        "invalidate",
        {},
        0,
        options
    );

end

--<< API Methods end >>--




--- Return API Methods as table
return update;
