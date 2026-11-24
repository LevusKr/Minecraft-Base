--[[
    Update CLI
    OpenOS command-line utility for checking, comparing and installing cluster file updates.
--]]


-- Libraries and components
local codec = require("cluster/codec");
local update = require("cluster/update-library");
local utils = require("cluster/utils");
local utils_string = require("cluster/utils-string");

local computer = require("computer");
local filesystem = require("filesystem");
local os = require("os");
local shell = require("shell");

local cwrite = utils_string.cwrite;
local parse_boolean = utils_string.parse_boolean;
--

-- Variables and Constants
local timeout_default = 10;
local quiet = false;
--




--<< Helper Functions >>--

--- Writes text to terminal (or specified stream) only when CLI is not running in quiet mode
local function qwrite(text, stream)

    cwrite(not quiet, text, stream);

end

local function print_usage()

    io.write([[
Usage: update [command] [options] [file...]

Commands:
  check                 Compare local files against server (default)
  download, install     Download and install available updates
  list                  List tracked files and local CRC32 checksums
  invalidate            Invalidate remote Update/NAS file caches
  sync-config           Sync '/etc/updates.cfg' from NAS-Server
  status                Show Update-Daemon status

Options:
  -c, --check           Only check for available updates
  -d, -u, --download    Download and install updates
  -f, --force           Force re-download even if checksums match
  -r, --reboot          Reboot automatically if updates were installed
  -l, --list            List tracked files from '/etc/updates.cfg'
  -i, --invalidate      Invalidate remote hash/chunk caches
  -s, --status          Query local Update-Daemon status
  -a, --async           Perform request asynchronously
  -t, --timeout=<sec>   Request timeout in seconds (default: 10)
      --file=<path>     Operate on specific individual file(s) (comma-separated)
      --direct          Transfer data directly from NAS (default)
      --no-direct       Tunnel data through Update-Server
      --bypass          Contact NAS-Server directly, bypassing Update-Server
      --delta           Use incremental delta updates (default)
      --no-delta        Disable incremental delta updates
      --daemon          Delegate execution to 'rc update-daemon'
  -v, --verbose         Print detailed per-file status
  -q, --quiet           Suppress standard output
  -h, --help            Display this help message
]]);

end

--- Pre-normalizes CLI arguments so OpenOS's shell.parse handles '-t=30', '-dt=30', '-t30', '-t 30', '--timeout 30', and '--file <path>' properly
local function parse_cli_args(...)

    local raw_args = { ... };
    local normalized = {};
    local i = 1;

    while i <= #raw_args do

        local arg = raw_args[ i ];

        if type( arg ) == "string" then

            --- Match single-dash option with '=' (e.g. '-t=30' or combined '-dt=30')
            local prefix_flags, key_flag, eq_val = arg:match("^%-(%a*)(%a)=(.+)$");

            if key_flag and eq_val then

                if prefix_flags and #prefix_flags > 0 then
                    normalized[ #normalized + 1 ] = "-" .. prefix_flags;
                end

                normalized[ #normalized + 1 ] = "--" .. key_flag .. "=" .. eq_val;

            elseif arg:match("^%-(%a*)t(%d+%.?%d*)$") then

                --- Match attached numeric timeout (e.g. '-t30' or combined '-dt30')
                local prefix_t, num_val = arg:match("^%-(%a*)t(%d+%.?%d*)$");

                if prefix_t and #prefix_t > 0 then
                    normalized[ #normalized + 1 ] = "-" .. prefix_t;
                end

                normalized[ #normalized + 1 ] = "--timeout=" .. num_val;

            elseif (arg == "-t" or arg == "--timeout") and raw_args[ i + 1 ] ~= nil and tonumber( raw_args[ i + 1 ] ) ~= nil then

                --- Match space-separated timeout (e.g. '-t 30' or '--timeout 30')
                normalized[ #normalized + 1 ] = "--timeout=" .. tostring( raw_args[ i + 1 ] );
                i = i + 1;

            elseif (arg == "--file" or arg == "--files") and type( raw_args[ i + 1 ] ) == "string" and raw_args[ i + 1 ]:sub(1, 1) ~= "-" then

                --- Match space-separated '--file <path>'
                normalized[ #normalized + 1 ] = "--file=" .. raw_args[ i + 1 ];
                i = i + 1;

            else

                normalized[ #normalized + 1 ] = arg;

            end

        else

            normalized[ #normalized + 1 ] = arg;

        end

        i = i + 1;

    end

    return shell.parse( table.unpack( normalized ) );

end

--- Lists all locally tracked files from '/etc/updates.cfg' with their size and CRC32 hash
local function command_list(filter, explicit_files)

    local success_list, files_or_err, count = update.list_local({
        reload = true,
        filter = filter,
        files  = explicit_files
    });

    if not success_list then

        cwrite(true, "Error: " .. tostring( files_or_err ) .. "\n", io.stderr);
        return 1;

    end

    qwrite("Tracked files in '/etc/updates.cfg' (" .. tostring( count ) .. "):\n\n");

    local existing_count = 0;
    local missing_count = 0;

    for _, file in ipairs( files_or_err ) do

        local exists = filesystem.exists( file );
        local hash = exists and update.hash_local_single( file ) or nil;
        local size = exists and filesystem.size( file ) or 0;

        if exists then
            existing_count = existing_count + 1;
        else
            missing_count = missing_count + 1;
        end

        local status_str = exists and string.format("%-10s  %8s", tostring( hash ), utils.math.adjust_value(size, "B")) or "MISSING             ";
        cwrite(true, string.format("  [%s]  %s\n", status_str, file));

    end

    qwrite("\nTotal: " .. tostring( count ) .. " files (" .. tostring( existing_count ) .. " local, " .. tostring( missing_count ) .. " missing).\n");


    return 0;

end

--<< Helper Functions end >>--




--<< CLI Execution >>--

local args, opts = parse_cli_args(...);

if opts.h or opts.help or args[1] == "help" then

    print_usage();
    return 0;

end


local action = "check";
local filter_files = {};
local legacy_mode = false;

--- Support legacy positional arguments: `update <download:bool> [async:bool] [timeout:number]`
if args[1] == "true" or args[1] == "false" or type( args[1] ) == "boolean" then

    legacy_mode = true;
    action = parse_boolean(args[1], false) and "download" or "check";

elseif args[1] then

    local sub = tostring( args[1] ):lower();

    if sub == "check" or sub == "compare" then

        action = "check";

    elseif sub == "download" or sub == "install" or sub == "upgrade" or sub == "update" then

        action = "download";

    elseif sub == "list" or sub == "ls" then

        action = "list";

    elseif sub == "invalidate" or sub == "flush" or sub == "clear-cache" then

        action = "invalidate";

    elseif sub == "sync-config" or sub == "sync" then

        action = "sync-config";

    elseif sub == "status" then

        action = "status";

    else

        --- First positional argument is a file path/filter
        filter_files[ #filter_files + 1 ] = args[1];

    end

    for i = 2, #args do
        filter_files[ #filter_files + 1 ] = args[ i ];
    end

end


--- Explicit option flags override subcommands
if opts.l or opts.list then
    action = "list";
elseif opts.i or opts.invalidate then
    action = "invalidate";
elseif opts.s or opts.status then
    action = "status";
elseif opts["sync-config"] then
    action = "sync-config";
elseif opts.d or opts.u or opts.download or opts.update or opts.install then
    action = "download";
elseif opts.c or opts.check then
    action = "check";
end


quiet = opts.q or opts.quiet or false;

local verbose = opts.v or opts.verbose or false;
local force = opts.f or opts.force or false;
local reboot = opts.r or opts.reboot or false;
local bypass = opts.bypass or false;
local use_daemon = opts.daemon or false;

local async =
    legacy_mode
    and parse_boolean(args[2], false)
    or (opts.a or opts.async or false)
;

local timeout = timeout_default;

if legacy_mode and tonumber( args[3] ) then
    timeout = tonumber( args[3] );
elseif tonumber( opts.t ) then
    timeout = tonumber( opts.t );
elseif tonumber( opts.timeout ) then
    timeout = tonumber( opts.timeout );
end

local direct = not opts["no-direct"] and parse_boolean(opts.direct, true);
local delta = not opts["no-delta"] and parse_boolean(opts.delta, true);
local explicit_files = (type( opts.file ) == "string" and opts.file) or (type( opts.files ) == "string" and opts.files) or nil;
local filter = (#filter_files > 0) and filter_files or nil;


--- Handle standalone commands
if action == "list" then

    return command_list(filter, explicit_files);

elseif action == "sync-config" then

    local success_sync = update.sync_config({
        write   = not quiet,
        timeout = timeout
    });

    return success_sync and 0 or 1;

elseif action == "status" then

    os.execute("rc update-daemon status");
    return 0;

elseif action == "invalidate" then

    qwrite("Invalidating remote Update-Server and NAS-Server caches...\n");

    local future_inv = update.invalidate({
        async         = async,
        timeout       = timeout,
        bypass_server = bypass
    });

    if not async then

        local res = future_inv and future_inv.result or {};

        cwrite(res.success and not quiet, tostring( res.result ) .. "\n");
        cwrite(not res.success, "Error: " .. tostring( res.result or "Failed to invalidate cache" ) .. "\n", io.stderr);

        return res.success and 0 or 1;

    end

    return 0;

end


local operation_options = {
    download      = (action == "download"),
    write         = not quiet,
    verbose       = verbose,
    async         = async,
    timeout       = timeout,
    direct        = direct,
    delta         = delta,
    force         = force,
    reboot        = reboot,
    filter        = filter,
    files         = explicit_files,
    bypass_server = bypass
};

--- Delegate to RC daemon if '--daemon' was specified
if use_daemon then

    os.execute("rc update-daemon _update " .. codec.encode( operation_options ));
    return 0;

end


--- Delegate directly to update-library
local time_start = computer.uptime();

local response_future = update.operate(
    action,
    operation_options
);

response_future:on_completion(
    function()

        local details = response_future.result or {};
        local elapsed = string.format("%.2f", computer.uptime() - time_start);

        if details.success then

            qwrite("\n" .. tostring( details.result ) .. " [" .. elapsed .. "s]\n");
            cwrite(not quiet and action == "check" and details.updates_available and #details.updates_available > 0, "Run 'update -d' to download and install available updates.\n");

        else

            cwrite(true, "\nUpdate failed: " .. tostring( details.result ) .. " [" .. elapsed .. "s]\n", io.stderr);

        end

    end
);

--<< CLI Execution end >>--
