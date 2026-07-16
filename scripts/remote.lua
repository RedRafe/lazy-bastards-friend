--- Public remote interface (DESIGN.md §10.1) — everything the mod's own script
--- can do, other mods and scenarios can do through here. Documented with
--- copy-paste examples in docs/API.md; keep the two in sync.

local State = require('__lazy-bastards-friend__.scripts.state')
local Watchdog = require('__lazy-bastards-friend__.scripts.watchdog')

--- @param channel any
--- @return LbfChannel
local function check_channel(channel)
    if channel ~= 'collect' and channel ~= 'feed' and channel ~= 'combat' then
        error("lazy-bastards-friend: unknown channel '" .. tostring(channel) .. "' (expected 'collect', 'feed' or 'combat')")
    end
    return channel
end

--- @param player_index any
--- @return LuaPlayer
local function check_player(player_index)
    local player = game.get_player(player_index)
    if not player then
        error('lazy-bastards-friend: no player with index ' .. tostring(player_index))
    end
    return player
end

--- @param global table<string, {enabled: boolean}>
--- @return table<LbfChannel, boolean>
local function channel_global_map(global)
    local map = {}
    for _, channel in pairs(State.channels) do
        map[channel] = global[channel].enabled
    end
    return map
end

--- @param player_settings table<string, {enabled: boolean, allowed: boolean}>
--- @return table<LbfChannel, boolean>
local function channel_enabled_map(player_settings)
    local map = {}
    for _, channel in pairs(State.channels) do
        map[channel] = player_settings[channel].enabled
    end
    return map
end

--- @param player_settings table<string, {enabled: boolean, allowed: boolean}>
--- @return table<LbfChannel, boolean>
local function channel_locked_map(player_settings)
    local map = {}
    for _, channel in pairs(State.channels) do
        map[channel] = not player_settings[channel].allowed
    end
    return map
end

-- Behavior/appearance flags exposed through set_player_flag / get_player_state.
-- Names match the settings-tree node ids (state.lua's TREE_DEF) one-to-one,
-- except 'summary' which isn't a tree node (DESIGN.md §12).
-- BREAKING (2026-07-16): renamed from the flat 'fuel'/'chests'/... names to
-- match the tree's family-prefixed ids — see changelog.txt / docs/API.md.
local FLAG_NAMES = {
    feed_fuel = true,
    feed_ingredients = true,
    collect_chests = true,
    collect_ground = true,
    feed_trash = true,
    summary = true,
    appearance_show_others = true,
    feed_rebalance = true,
    appearance_starvation = true,
}

--- @param flag any
--- @return string
local function check_flag(flag)
    if not FLAG_NAMES[flag] then
        error("lazy-bastards-friend: unknown flag '" .. tostring(flag) .. "' (see docs/API.md)")
    end
    return flag
end

remote.add_interface('lazy-bastards-friend', {
    --- The global whole-mod switch (the admin GUI's "Everyone" On/Off).
    --- Preserves channel masters and per-player settings; does not touch the
    --- SPM watchdog.
    --- @param value boolean
    set_global_master = function(value)
        State.set_global_master(value == true)
        State.refresh_all()
    end,

    --- Global master switch for one channel. Does not touch the SPM watchdog —
    --- re-arming after a trip goes through set_watchdog_enabled(true).
    --- @param channel LbfChannel
    --- @param value boolean
    set_active = function(channel, value)
        State.set_master(check_channel(channel), value == true)
        State.refresh_all()
    end,

    --- @param channel LbfChannel
    --- @return boolean
    get_active = function(channel)
        return storage.settings[check_channel(channel)].enabled
    end,

    --- Admin lock: while locked the channel is off for that player regardless
    --- of their own preference.
    --- @param player_index uint
    --- @param channel LbfChannel
    --- @param locked boolean
    lock_player = function(player_index, channel, locked)
        local player = check_player(player_index)
        State.set_locked(player.index, check_channel(channel), locked == true)
        State.refresh(player)
    end,

    --- Admin master lock: while locked the whole mod is off for that player,
    --- every channel, regardless of their own preferences (which are kept).
    --- The "On/Off" column of the admin GUI's player list.
    --- @param player_index uint
    --- @param locked boolean
    lock_player_master = function(player_index, locked)
        local player = check_player(player_index)
        State.set_locked_master(player.index, locked == true)
        State.refresh(player)
    end,

    --- The player's own toggle, as if they clicked it in their panel.
    --- @param player_index uint
    --- @param channel LbfChannel
    --- @param enabled boolean
    set_player_enabled = function(player_index, channel, enabled)
        local player = check_player(player_index)
        State.set_player_enabled(player, check_channel(channel), enabled == true)
        State.refresh(player)
    end,

    --- @param player_index uint
    --- @return table see docs/API.md
    get_player_state = function(player_index)
        local player = check_player(player_index)
        local data = State.get_player_data(player.index)
        local effective = {}
        for _, channel in pairs(State.channels) do
            effective[channel] = State.effective(player.index, channel)
        end
        local reserves = {}
        for name, count in pairs(data.reserves) do
            reserves[name] = count
        end
        local flags = {}
        for name in pairs(FLAG_NAMES) do
            if name == 'summary' then
                flags[name] = data.summary_enabled == true
            else
                flags[name] = data.settings[name].enabled == true
            end
        end
        return {
            enabled = channel_enabled_map(data.settings),
            locked = channel_locked_map(data.settings),
            locked_master = not data.settings.mod.allowed,
            effective = effective,
            radius = State.get_radius(player.index),
            shape = data.shape,
            flags = flags,
            reserves = reserves,
        }
    end,

    --- A player's behavior toggle, as if they clicked it in their panel.
    --- @param player_index uint
    --- @param flag string see FLAG_NAMES / docs/API.md
    --- @param value boolean
    set_player_flag = function(player_index, flag, value)
        local player = check_player(player_index)
        check_flag(flag)
        if flag == 'summary' then
            State.get_player_data(player.index).summary_enabled = value == true
            State.push_setting(player, 'lbf-show-summary')
        else
            State.set_enabled(player, flag, value == true)
        end
        State.refresh(player)
    end,

    --- Clamped to the lbf-min-radius / lbf-max-radius map settings.
    --- @param player_index uint
    --- @param radius number
    set_player_radius = function(player_index, radius)
        local player = check_player(player_index)
        if type(radius) ~= 'number' then
            error('lazy-bastards-friend: radius must be a number')
        end
        State.set_radius(player, radius)
        State.refresh(player)
    end,

    --- @return table see docs/API.md
    get_state = function()
        return {
            master = storage.settings.mod.enabled ~= false,
            active = channel_global_map(storage.settings),
            auto_disabled = storage.auto_disabled == true,
            watchdog = Watchdog.status(),
            spm_threshold = settings.global['lbf-spm-threshold'].value,
        }
    end,

    --- Set the lbf-spm-threshold map setting. Runtime-global settings can only
    --- be written by the mod that owns them, so scenarios/other mods must go
    --- through here. Fires the usual setting-changed handling (debounce reset).
    --- @param value number
    set_spm_threshold = function(value)
        if type(value) ~= 'number' or value < 0 then
            error('lazy-bastards-friend: threshold must be a non-negative number')
        end
        settings.global['lbf-spm-threshold'] = { value = value }
    end,

    --- The watchdog on/off switch (also the lbf-watchdog-enabled map setting).
    --- Turning it on un-trips and re-arms after an auto-retirement — the only
    --- re-arm path; set_active(..., true) alone leaves the watchdog tripped.
    --- @param value boolean
    set_watchdog_enabled = function(value)
        Watchdog.set_enabled(value == true)
    end,

    --- Current science-per-minute reading for a force (what the watchdog sees).
    --- @param force ForceID
    --- @return double
    get_spm = function(force)
        local kind = type(force)
        local force_object = (kind == 'string' or kind == 'number') and game.forces[force] or force
        if not force_object or force_object.object_name ~= 'LuaForce' or not force_object.valid then
            error('lazy-bastards-friend: no force ' .. tostring(force))
        end
        return Watchdog.spm(force_object)
    end,

    --- Per-item minimum the mod never dips below when feeding (nil clears).
    --- @param player_index uint
    --- @param item_name string
    --- @param count uint?
    set_player_reserve = function(player_index, item_name, count)
        local player = check_player(player_index)
        if not prototypes.item[item_name] then
            error("lazy-bastards-friend: unknown item '" .. tostring(item_name) .. "'")
        end
        if count ~= nil and (type(count) ~= 'number' or count < 0) then
            error('lazy-bastards-friend: count must be nil or a non-negative number')
        end
        State.get_player_data(player.index).reserves[item_name] = count and math.floor(count) or nil
    end,

    --- Exclude/include one entity from this player's raids (DESIGN.md §10.4),
    --- as if hovering it and pressing the exclude hotkey. Unlike the hotkey
    --- path this takes a bare unit_number (no LuaEntity handle), so it cannot
    --- register cleanup on the entity's destruction — callers that exclude an
    --- entity through this call are responsible for clearing it again if the
    --- entity might outlive their own bookkeeping.
    --- @param player_index uint
    --- @param unit_number uint
    --- @param excluded boolean
    set_entity_excluded = function(player_index, unit_number, excluded)
        local player = check_player(player_index)
        if type(unit_number) ~= 'number' then
            error('lazy-bastards-friend: unit_number must be a number')
        end
        State.get_player_data(player.index).excluded[unit_number] = excluded == true or nil
        State.get_player_data(player.index).cache = nil
    end,

    --- @param player_index uint
    --- @param unit_number uint
    --- @return boolean
    is_entity_excluded = function(player_index, unit_number)
        local player = check_player(player_index)
        return State.get_player_data(player.index).excluded[unit_number] == true
    end,
})
