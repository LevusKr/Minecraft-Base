--[[
    File-Utils-Library
    This library provides enhanced functionality for files,
    such as reading and writing.
--]]


-- Libraries and components
local component = require("component");
local event = require("event");
local filesystem = require("filesystem");

local data = component.isAvailable("data") and component.data or nil;
--

-- Data tables
local utils_file = {};

local handles = {};
--




--<< API Methods >>--

--- Reads data from file. 'file' is either a path or a file handle
function utils_file.read(file, options)

    options = options or {};


    local is_handle = type( file ) == "table";
    local handle = is_handle and file or nil;


    if not is_handle and not filesystem.exists( file ) then

        return false, "Not existing: " .. tostring( file );

    end


    if not is_handle then

        local open_error = nil;
        handle, open_error = io.open(file, "r" .. (options.binary and "b" or ""));

        if not handle then

            return false, "Could not open '" .. tostring( file ) .. "': " .. tostring( open_error );

        end

    end


    local result = handle:read(options.count or "*a");

    if not options.keep_open then

        handle:close();
        handle = nil;

    end


    return true, result, handle;

end

function utils_file._read(path, binary)

    --- If file doesn't exist, return nil
    if not filesystem.exists( path ) then
        return nil;
    end


    local content = nil;
    local file = io.open(path, "r" .. (binary and "b" or ""));

    if file then

        content = file:read("*a");
        file:close();

    end

    return content;

end

--- Recursively creates given directory path segment by segment if it does not exist yet
function utils_file.mkdir(directory)

    if not directory or directory == "" or directory == "/" then
        return true;
    end

    if filesystem.exists( directory ) then
        return filesystem.isDirectory( directory );
    end


    local segments = filesystem.segments( directory );
    local current = "";

    for _, segment in ipairs( segments ) do

        current = current .. "/" .. segment;

        if not filesystem.exists( current ) then

            filesystem.makeDirectory( current );

        end

    end


    return filesystem.exists( directory );

end

function utils_file.write(file, data, options)

    options = options or {};


    local is_handle = type( file ) == "table";
    local handle = is_handle and file or nil;


    if not is_handle then

        local dir = filesystem.path( file );

        if dir and dir ~= "" and not filesystem.exists( dir ) then

            utils_file.mkdir( dir );

        end


        local open_error = nil;
        handle, open_error = io.open(file, (options.append and "a" or "w") .. (options.binary and "b" or ""));

        if not handle then

            return false, "Could not open '" .. tostring( file ) .. "': " .. tostring( open_error );

        end

    end


    local _file, write_error = handle:write( data );

    if not _file then

        if not options.keep_open then
            pcall(handle.close, handle);
        end

        return false, write_error;

    end

    handle = _file;


    if not options.keep_open then

        handle:flush();
        handle:close();

        handle = nil;

    end


    return true, "result", handle;

end

function utils_file._write(path, data, append, binary)
    if type( path ) == "string" then
        local dir = filesystem.path( path );

        if dir and dir ~= "" and not filesystem.exists( dir ) then
            utils_file.mkdir( dir );
        end
    end

    local file = type(path) == "string"
        and assert(io.open(path, (append and "a" or "w") .. (binary and "b" or "")))
        or path; -- open file in write or append mode. additionally binary

    if file then
        file:write(data);
        file:flush();
        file:close();
        return true;
    end


    return false;
end

function utils_file.list(directory, path)
    local path_filesystem = filesystem.get(path or directory);

    if not path_filesystem then
        return false, "No valid filesystem";
    end


    if not path_filesystem.exists(directory) then
        return false, "Not existing";
    end


    if not path_filesystem.isDirectory(directory) then
        return false, "Not a directory";
    end



    local list = path_filesystem.list(directory);


    return true, list;
end

--- Normalizes and joins two path segments without duplicate slashes, ensuring a leading slash
function utils_file.join_path(parent_path, child_path)

    parent_path = tostring( parent_path or "" );
    child_path = tostring( child_path or "" );

    if parent_path == "" then
        return child_path;
    end

    if child_path == "" then
        return parent_path;
    end


    local joined = nil;

    if parent_path:sub(-1) == "/" and child_path:sub(1, 1) == "/" then

        joined = parent_path .. child_path:sub(2);

    elseif parent_path:sub(-1) ~= "/" and child_path:sub(1, 1) ~= "/" then

        joined = parent_path .. "/" .. child_path;

    else

        joined = parent_path .. child_path;

    end

    if joined:sub(1, 1) ~= "/" then
        joined = "/" .. joined;
    end


    return joined;

end

--- Checks whether a file path matches an optional filter (string or table of strings)
function utils_file.matches(file_path, filter)

    if not filter then
        return true;
    end

    if type( filter ) == "string" then

        if filter == "" then
            return true;
        end

        return (file_path == filter)
            or (filesystem.name( file_path ) == filter)
            or (file_path:find(filter, 1, true) ~= nil);

    elseif type( filter ) == "table" then

        if #filter == 0 then
            return true;
        end

        for _, pattern in ipairs( filter ) do

            if utils_file.matches(file_path, pattern) then
                return true;
            end

        end

        return false;

    end


    return true;

end

--- Recursively resolves a nested folder/file configuration table into a sorted flat list of file paths
function utils_file.resolve_tree(source_table, filter)

    if type( source_table ) ~= "table" then
        return false, "Source table is not a table", 0;
    end


    local files = {};
    local seen = {};

    local read_file_paths;
    read_file_paths = function(current_table, parent_path)

        for key, entry in pairs( current_table ) do

            if type( entry ) == "table" then

                local next_parent =
                    type( key ) == "string"
                    and utils_file.join_path(parent_path, key)
                    or parent_path
                ;

                read_file_paths(entry, next_parent);

            elseif type( entry ) == "string" then

                local full_path = utils_file.join_path(parent_path, entry);

                if not seen[ full_path ] and utils_file.matches(full_path, filter) then

                    seen[ full_path ] = true;
                    files[ #files + 1 ] = full_path;

                end

            end

        end

    end

    read_file_paths(source_table, "");

    table.sort( files );


    return true, files, #files;

end

--- Computes CRC32 checksum of a file path or raw content string
function utils_file.hash(file_or_content, is_content)

    assert(data, "No data card available");


    local content = is_content and file_or_content or utils_file._read(file_or_content, true);

    if content then

        local max_hash_size = 8000;

        if #content <= max_hash_size then

            local checksum = data.crc32( content );
            return checksum, content;

        end


        local direct_checksum = data.crc32( content );

        if direct_checksum then

            return direct_checksum, content;

        end


        local part_hashes = {};
        local total_parts = math.ceil(#content / max_hash_size);

        for part_index = 1, total_parts do

            local part_start = (part_index - 1) * max_hash_size + 1;
            local part_end = part_index * max_hash_size;
            part_hashes[ part_index ] = data.crc32( content:sub(part_start, part_end) ) or "";

        end

        local combined_checksum = data.crc32( table.concat(part_hashes, "") );
        return combined_checksum, content;

    end

    return nil, nil;

end

--- Splits file content into content-anchored chunks (preferring function/section boundaries or line breaks)
function utils_file.chunk(content, chunk_size_max)

    if not content or content == "" then
        return {};
    end


    chunk_size_max = chunk_size_max or 1024;

    local chunks = {};
    local length = #content;
    local position = 1;

    while position <= length do

        local remaining = length - position + 1;

        if remaining <= chunk_size_max then

            local _, delimiter_end = content:find("\r?\n\r?\n", position);

            if delimiter_end then

                chunks[ #chunks + 1 ] = content:sub(position, delimiter_end);
                position = delimiter_end + 1;

            else

                chunks[ #chunks + 1 ] = content:sub(position, length);
                position = length + 1;

            end

        else

            local window_end = position + chunk_size_max - 1;
            local window = content:sub(position, window_end);
            local _, delimiter_end = window:find("\r?\n\r?\n");

            if delimiter_end then

                local split_at = position + delimiter_end - 1;
                chunks[ #chunks + 1 ] = content:sub(position, split_at);
                position = split_at + 1;

            else

                local last_newline = window:match("^.*()\n");

                if last_newline and last_newline > 1 then

                    local split_at = position + last_newline - 1;
                    chunks[ #chunks + 1 ] = content:sub(position, split_at);
                    position = split_at + 1;

                else

                    chunks[ #chunks + 1 ] = window;
                    position = window_end + 1;

                end

            end

        end

    end


    return chunks;

end

--- Computes CRC32 hashes for a list of content chunks
function utils_file.hash_chunks(chunks)

    assert(data, "No data card available");


    local hashes = {};

    for index = 1, #chunks do

        hashes[ index ] = data.crc32( chunks[ index ] );

    end


    return hashes;

end

--- Computes a compact delta operation list between client chunk hashes and remote chunks
function utils_file.compute_delta(client_chunk_hashes, remote_chunks, remote_chunk_hashes, full_size)

    if type( client_chunk_hashes ) ~= "table" or #client_chunk_hashes == 0 or #remote_chunks == 0 then
        return false;
    end


    local client_lookup = {};

    for index, hash in ipairs( client_chunk_hashes ) do

        if not client_lookup[ hash ] then
            client_lookup[ hash ] = index;
        end

    end


    local ops = {};
    local literal_bytes = 0;
    local matched_chunks = 0;

    for r_index = 1, #remote_chunks do

        local r_hash = remote_chunk_hashes[ r_index ];
        local match_index = client_lookup[ r_hash ];

        if match_index then

            matched_chunks = matched_chunks + 1;

            local prev = ops[ #ops ];

            if type( prev ) == "number" and prev == (match_index - 1) then

                ops[ #ops ] = { prev, match_index };

            elseif type( prev ) == "table" and prev[2] == (match_index - 1) then

                prev[2] = match_index;

            else

                ops[ #ops + 1 ] = match_index;

            end

        else

            local chunk_str = remote_chunks[ r_index ];

            if type( ops[ #ops ] ) == "string" then

                ops[ #ops ] = ops[ #ops ] .. chunk_str;

            else

                ops[ #ops + 1 ] = chunk_str;

            end

            literal_bytes = literal_bytes + #chunk_str;

        end

    end


    if matched_chunks == 0 then
        return false;
    end

    local estimated_delta_size = literal_bytes + (#ops * 8);

    if estimated_delta_size >= (full_size * 0.85) then
        return false;
    end


    return true, ops, math.max(0, full_size - literal_bytes);

end

--- Reconstructs full file content from local chunks (or a local file path) and remote delta operations
function utils_file.apply_delta(local_chunks_or_path, ops)

    if type( ops ) ~= "table" then
        return false, "Invalid delta operations";
    end


    local local_chunks = local_chunks_or_path;

    if type( local_chunks_or_path ) == "string" then

        local current_content = utils_file._read(local_chunks_or_path, true);

        if not current_content then
            return false, "Local base file not found for delta reconstruction";
        end

        local_chunks = utils_file.chunk( current_content );

    end

    if type( local_chunks ) ~= "table" then
        return false, "Invalid local chunks for delta reconstruction";
    end


    local parts = {};

    for _, op in ipairs( ops ) do

        if type( op ) == "number" then

            local chunk = local_chunks[ op ];

            if not chunk then
                return false, "Missing local chunk #" .. tostring( op );
            end

            parts[ #parts + 1 ] = chunk;

        elseif type( op ) == "table" then

            local start_idx = op[1];
            local end_idx = op[2];

            if not start_idx or not end_idx or start_idx > end_idx then
                return false, "Malformed chunk range in delta";
            end

            for idx = start_idx, end_idx do

                local chunk = local_chunks[ idx ];

                if not chunk then
                    return false, "Missing local chunk #" .. tostring( idx );
                end

                parts[ #parts + 1 ] = chunk;

            end

        elseif type( op ) == "string" then

            parts[ #parts + 1 ] = op;

        else

            return false, "Unsupported delta operation type: " .. type( op );

        end

    end


    return true, table.concat(parts, "");

end

--<< API Methods end >>--




--- Return API Methods as table
return utils_file;
