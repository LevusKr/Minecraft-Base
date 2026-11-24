--- @module 'cluster/utils-crypt'
--[[
    Crypt-Utils-Library
    This library provides enhanced functionality for en-/decrypting,
    such as managing key-pairs, XXX.
--]]


-- Libraries and components
local Cache = require("cluster/cache");
local utils_file = require("cluster/utils-file");

local component = require("component");
local event = require("event");


local data = component.data;
--

-- Data tables
local utils_crypt = {};


---
local function cache_reload(arg, type)

    local success, result = utils_crypt.load(type, arg);

    if not success then

        event.onError( tostring( result ) );

        return nil;

    end

    return result;

end

--- This cache holds all locally stored public keys. TTL of math.huge
utils_crypt.cache_keys_public = Cache.create(
    cache_reload,
    math.huge,
    "public" --- Passed to cache_reload as 'type'
);

--- This cache holds all locally stored private keys. TTL of math.huge
utils_crypt.cache_keys_private = Cache.create(
    cache_reload,
    math.huge,
    "private" --- Passed to cache_reload as 'type'
);

--- This cache holds all locally stored ECDH crypt keys. TTL of math.huge
utils_crypt.cache_keys_crypt = Cache.create(
    cache_reload,
    math.huge,
    "crypt" --- Passed to cache_reload as 'type'
);
---
--




--<< API Methods >>--

--- Randomly generates keypair of private and public keys and stores it in "/etc/keys/"
--- @param name string? Name of keypair, leave blank for general keypair
--- 
--- @return boolean success #Success of keypair generation
--- @return userdata|string #Generated public key or keypair generation error
--- @return userdata? #Generated private key or nil
--- @return table? result_store {key_public={success=boolean, result=string}, key_private={success=boolean,result=string}}
function utils_crypt.generate_keypair(name)

    local execution = {pcall( data.generateKeyPair )};

    local success = execution[1];

    --- Only present if execution failed
    local result = execution[2];
    ---

    --- Only present if execution succeeded
    local key_public = execution[2];
    local key_private = execution[3];
    ---


    if success then

        local success_public_key, result_public_key = utils_crypt.store(key_public, name);

        local success_private_key, result_private_key = utils_crypt.store(key_private, name);

        local result_store = {
            key_public = {
                success = success_public_key,
                result = result_public_key
            },
            key_private = {
                success = success_private_key,
                result = result_private_key
            }
        };


        return true, key_public, key_private, result_store;

    end


    return false, result;

end

--- Generates ECDH key from machine's local private and given public key. 'counterpart' is either said public key object or a key name pointing to a key in "/etc/keys/"
function utils_crypt.generate_key_crypt(counterpart)

    local is_key = type( counterpart ) == "table";


    local key_public = is_key and counterpart or nil;

    --- If 'counterpart' is a name, not a public key object, try to retrieve locally stored key for that name
    if not is_key then

        --- Use uncached method here to avoid cluttering the cache with never-to-be-used keys since the crypt key is what we're doing here
        local success_key_public, result_key_public = utils_crypt.load("public", counterpart);

        if not success_key_public then

            return false, result_key_public; --- 'result_key_public' is an error message, so pass it on

        end


        key_public = result_key_public;

    end
    

    --- Retrieve machine's local private key
    local success_key_private, key_private = utils_crypt.key_private();

    if not success_key_private then

        return false, key_private; --- 'key_private' is an error message, so pass it on

    end


    local key_crypt = data.md5( data.ecdh(key_private, key_public) );

    --- If 'counterpart' was a name instead of a key object, store ECDH crypt key for later reusing (see top)
    if not is_key then

        local success_store, result_store = utils_crypt.store(key_crypt, tostring( counterpart ));

        -- NOTE: don't add to cache here, cache is inside network library thus creating cyclic dependency if required

    end


    return true, key_crypt;

end


--- Retrieves (general or named) private key from the local cache, otherwise tries to retrieve it from "/etc/keys/".
--- Key name is 'private_$name.key', or 'private.key' if no name is given.
--- 
--- @param name string?
--- @param refresh boolean?
--- 
--- @return userdata? #Deserialized key object
function utils_crypt.key_private(name, refresh)

    return utils_crypt.cache_keys_private:get(name, refresh, "private");

end

--- Retrieves (general or named) public key from the local cache, otherwise tries to retrieve it from "/etc/keys/".
--- Key name is 'public_$name.key', or 'public.key' if no name is given.
--- 
--- @param name string?
--- @param refresh boolean?
--- 
--- @return userdata? #Deserialized key object
function utils_crypt.key_public(name, refresh)

    return utils_crypt.cache_keys_public:get(name, refresh, "public");

end

--- Retrieves (general or named) ECDH crypt key from the local cache, otherwise tries to retrieve it from "/etc/keys/".
--- If that also fails and 'name' is an existing public key name or a key object, a new
--- ECDH crypt key is generated using that public key and the local private key.
--- Key name is 'crypt_$name.key'. If empty, 'public_$name.key' is then searched for generation
--- 
--- @param name string?
--- @param refresh boolean?
--- 
--- @return string? #MD5 Hash of retrieved/generated ECDH crypt key
function utils_crypt.key_crypt(name, refresh)

    return utils_crypt.cache_keys_crypt:get(name, refresh, "crypt");

end


--- Stores given key under given name as '/etc/keys/${type}_${name}.key'
function utils_crypt.store(key, name)

    --- Determine key type
    local key_type = "crypt";

    if type( key ) ~= "string" then

        key_type =
            key.isPublic()
            and "public"
            or "private"
        ;

    end

    local path = "/etc/keys/" .. key_type .. tostring(name and ("_" .. name) or "") .. ".key";


    --- Write key to disk (if key object, serialize at first; this allows ECDH crypt keys to be written directly as string)
    local success, result = utils_file.write(
        path,

        key_type == "crypt"
            and key
            or key.serialize()
        ,

        {binary = true}
    );


    return success, result;

end

--- Reads key under given name from '/etc/keys/'. Name MUST NOT contain type as prefix and .key as suffix (e.g. public_HOSTNAME.key)
function utils_crypt.load(_type, name)

    if _type ~= "public" and _type ~= "private" and _type ~= "crypt" then

        return false, "Key type must be 'public', 'private' or 'crypt'";

    end


    --- Own private or public keys have no specific 'name' (private|public.key), so add that suffix only if 'name' is given
    local path = "/etc/keys/" .. _type;
    path =

        name

        and path .. "_" .. tostring( name )

        or path

    ;
    path = path .. ".key";


    local success, result;


    --- Since the retrieving (generation, actually) of crypt keys is a little more involving and also checks for a public key under the same name, handle this seperatly here
    if _type == "crypt" then

        --- Whether this function has been called with a (remote) public key and thus is expected to generate an ECDH crypt key
        local is_key = type( name ) == "table";

        --- If 'name' is indeed no key object (see above), but a key name, first try to retrieve corresponding ECDH crypt key from disk
        if not is_key then

            success, result = utils_file.read(path, {binary = true});

            --- If there is an ECDH crypt key stored for that name, return it; If not, continue and...
            if success then
                return true, result;
            end

        end

        --- ...possibly recalculate ECDH crypt key. This involves checking for a locally stored public key under 'name'
        success, result = utils_crypt.generate_key_crypt( name ); --- 'name' is public key object or public key name

        --- Return formatted error message instead of 'result'
        if not success then

            name =
                is_key
                and ""
                or " '" .. tostring( name ) .. "'"
            ;

            return false, "Unable to retrieve local crypt key" .. name .. ": " .. (tostring( result ) or "File not found") .. debug.traceback();

        end

        return true, result;

    end


    success, result = utils_file.read(path, {binary = true});

    if not success then

        name =
            name
            and " '" .. tostring( name ) .. "'"
            or ""
        ;

        return false, "Unable to retrieve local " .. _type .. " key" .. name .. ": " .. (tostring( result ) or "File not found");

    end


    --- Only deserialize public and private keys, since ECDH crypt keys are strings
    result =
        _type ~= "crypt"
        and data.deserializeKey(
            result,
            "ec-" .. _type
        )
        or result
    ;


    return success, result;

end


--- Randomly generates Initialization Vector for encryption
function utils_crypt.generate_iv()

    return data.random(16);

end

function utils_crypt.generate_random(length)

    return data.random(length or 6);

end

--<< API Methods end >>--




--- Return API Methods as table
return utils_crypt;