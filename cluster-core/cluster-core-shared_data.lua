local shared_data = {};


-- Files and Configurations
shared_data.file_log = "/var/log/cluster/core-%s.log";

shared_data.file_nodes = "/etc/nodes.cfg";
--

-- Libraries and components
local Config = require("cluster/config");
local constants = require("cluster/constants");
local utils = require("cluster/utils");
local utils_crypt = require("cluster/utils-crypt");

local component = require("component");
local computer = require("computer");
local os = require("os");


shared_data.modem = component.modem;
shared_data.data = component.data;
--

-- Variables and constants
shared_data.logger = nil;
shared_data.log_print = false;
shared_data.log_debug = false;
shared_data.log_verbose = false;
shared_data.log_buffer = true;

shared_data.terminal = nil;

shared_data.hostname = utils.internal.hostname();
shared_data.message_wake = shared_data.modem.address..shared_data.hostname;

shared_data.encrypt_network = true;
shared_data.key_private = nil;
shared_data.key_public = nil;


shared_data.running = false;
shared_data.publishing = false;


shared_data.loop_interval = 5; --- Seconds between runs
shared_data.packet_processor_interval = 0.2; --- Seconds between runs
shared_data.alive_processor_interval = 0.2; --- Seconds between runs
--

-- Data tables
shared_data.nodes = Config:create( shared_data.file_nodes ); --- {123abc = {name = "node-n", address = "123abc", state = false, ttl = 5}, ...}
shared_data.nodes_by_name = {};
--




--- Update volatile booleans locally and respective environmental variables ---

function shared_data.update_var_running(state)

    shared_data.running = state;
    os.setenv(constants.env.running, state);

end

function shared_data.update_var_publishing(state)

    shared_data.publishing = state;
    os.setenv(constants.env.publishing, state);

end

---

--- Try to load the local key pair or if not possible, generate new one
--- NOTE: (uncached) methods because likely loaded for the first time and stored|cached here anyways
--- NOTE: switched to cached methods to remove only reference of key_*0 methods to change library structure
function shared_data.retrieve_keys()

    local success_key_public, key_public = utils_crypt.key_public();

    if success_key_public then

        shared_data.key_public = key_public;

    end


    local success_key_private, key_private = utils_crypt.key_private();

    if success_key_private then

        shared_data.key_private = key_private;

    end


    --- If one of the keys could not be loaded, generate new keypair (is this useful?; when an i/o error occurs, all references to this public key from other machines are invalid)
    if not success_key_public or not success_key_private then

        local success_keypair, key_public, key_private = utils_crypt.generate_keypair();

        --- If keys are successfully generated, succeed but give notice about regeneration
        if success_keypair then

            shared_data.key_public = key_public;
            shared_data.key_private = key_private;

            return true, "Regenerated";

        else

            local message_error = "Could not retrieve and/or generate local key pair. Encryption is unavailable: " .. tostring( key_public );

            -- event.onError( message_error );

            return false, message_error;

        end

    end


    return true;

end




---




--- Return library table
return shared_data;