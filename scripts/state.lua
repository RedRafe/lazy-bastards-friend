--- Storage schema, per-player data access, and the tri-state activation model
--- (effective = master AND NOT locked AND enabled, per channel). See DESIGN.md §2, §9.

local State = {}

--- @alias LbfChannel 'collect'|'feed'|'combat'

--- @type LbfChannel[]
State.channels = { 'collect', 'feed', 'combat' }

-- Refresh handlers are registered once at require time by control.lua (rendering,
-- GUI sync, shortcut sync) and invoked whenever a player's effective state, radius,
-- or appearance may have changed. Keeps state.lua free of GUI/render dependencies.
--- @type fun(player: LuaPlayer)[]
local refresh_handlers = {}

--- @param handler fun(player: LuaPlayer)
function State.add_refresh_handler(handler)
    refresh_handlers[#refresh_handlers + 1] = handler
end

--- @param player LuaPlayer
function State.refresh(player)
    if not player.valid then
        return
    end
    for _, handler in pairs(refresh_handlers) do
        handler(player)
    end
end

function State.refresh_all()
    for _, player in pairs(game.players) do
        State.refresh(player)
    end
end

--- Idempotent storage setup, safe for on_init and on_configuration_changed.
function State.init()
    storage.version = 1
    storage.active = storage.active or { collect = true, feed = true, combat = true }
    storage.auto_disabled = storage.auto_disabled or false
    storage.spm_strikes = storage.spm_strikes or 0
    storage.scheduler = storage.scheduler or { queue = {}, cursor = 1 }
    storage.admin_guis = storage.admin_guis or {}
    storage.players = storage.players or {}
    storage.items_moved = storage.items_moved or 0
    -- Backfill flags added after a player's record was created (checkbox
    -- states must be booleans, never nil), and drop reserves whose item
    -- prototype no longer exists (mod removed).
    for _, data in pairs(storage.players) do
        local flags = data.flags
        if flags.trash == nil then
            flags.trash = false
        end
        if flags.summary == nil then
            flags.summary = false
        end
        if flags.rebalance == nil then
            flags.rebalance = false
        end
        if flags.starvation == nil then
            flags.starvation = false
        end
        data.summary = data.summary or { collected = {}, fed = {}, next_flush = 0 }
        data.excluded = data.excluded or {}
        for name in pairs(data.reserves) do
            if not prototypes.item[name] then
                data.reserves[name] = nil
            end
        end
    end
end

--- @class LbfPlayerData
--- @field enabled table<LbfChannel, boolean>
--- @field locked table<LbfChannel, boolean>
--- @field radius uint
--- @field shape 'circle'|'square'
--- @field use_player_color boolean
--- @field color Color
--- @field fill boolean
--- @field opacity double
--- @field flags table<string, boolean>
--- @field reserves table<string, uint>
--- @field excluded table<uint, boolean> unit_number -> excluded from this player's raids (§10.4)
--- @field cache {key: string, tick: uint, x: double, y: double, entities: LuaEntity[]}?
--- @field render {edge: LuaRenderObject?, fill: LuaRenderObject?}
--- @field idle uint
--- @field gui_version uint
--- @field summary {collected: table<string, integer>, fed: table<string, integer>, next_flush: uint}

--- @param player_index uint
--- @return LbfPlayerData
function State.get_player_data(player_index)
    local data = storage.players[player_index]
    if not data then
        data = {
            enabled = { collect = true, feed = true, combat = true },
            locked = { collect = false, feed = false, combat = false },
            radius = 16,
            shape = 'circle',
            use_player_color = true,
            color = { r = 1, g = 0.5, b = 0, a = 1 },
            fill = true,
            opacity = 0.08,
            flags = {
                fuel = true,
                ingredients = true,
                chests = false,
                ground = false,
                trash = false,
                summary = false,
                show_others = false,
                rebalance = false,
                starvation = false,
            },
            reserves = {},
            excluded = {},
            render = {},
            idle = 0,
            gui_version = 0,
            summary = { collected = {}, fed = {}, next_flush = 0 },
        }
        storage.players[player_index] = data
    end
    return data
end

--- Per-player mod settings kept in sync with storage (DESIGN.md §8): each entry
--- mirrors one storage.players[i] field, both ways, so admins/players can drive
--- the mod from the in-game settings screen as well as the relative GUI.
--- @type table<string, {get: fun(data: LbfPlayerData): any, set: fun(data: LbfPlayerData, value: any)}>
local PLAYER_SETTINGS = {
    ['lbf-radius'] = {
        get = function(data) return data.radius end,
        set = function(data, value) data.radius = State.clamp_radius(value) end,
    },
    ['lbf-feed-fuel'] = {
        get = function(data) return data.flags.fuel end,
        set = function(data, value) data.flags.fuel = value end,
    },
    ['lbf-feed-ingredients'] = {
        get = function(data) return data.flags.ingredients end,
        set = function(data, value) data.flags.ingredients = value end,
    },
    ['lbf-take-chests'] = {
        get = function(data) return data.flags.chests end,
        set = function(data, value) data.flags.chests = value end,
    },
    ['lbf-pickup-ground'] = {
        get = function(data) return data.flags.ground end,
        set = function(data, value) data.flags.ground = value end,
    },
    ['lbf-drain-trash'] = {
        get = function(data) return data.flags.trash end,
        set = function(data, value) data.flags.trash = value end,
    },
    ['lbf-show-summary'] = {
        get = function(data) return data.flags.summary end,
        set = function(data, value) data.flags.summary = value end,
    },
    ['lbf-rebalance'] = {
        get = function(data) return data.flags.rebalance end,
        set = function(data, value) data.flags.rebalance = value end,
    },
    ['lbf-show-starvation'] = {
        get = function(data) return data.flags.starvation end,
        set = function(data, value) data.flags.starvation = value end,
    },
    ['lbf-shape'] = {
        get = function(data) return data.shape end,
        set = function(data, value) data.shape = value == 'square' and 'square' or 'circle' end,
    },
    ['lbf-fill-area'] = {
        get = function(data) return data.fill end,
        set = function(data, value) data.fill = value end,
    },
    ['lbf-opacity'] = {
        get = function(data) return math.floor(data.opacity * 100 + 0.5) end,
        set = function(data, value) data.opacity = value / 100 end,
    },
    ['lbf-use-my-color'] = {
        get = function(data) return data.use_player_color end,
        set = function(data, value) data.use_player_color = value end,
    },
    ['lbf-color'] = {
        get = function(data) return data.color end,
        set = function(data, value) data.color = { r = value.r, g = value.g, b = value.b, a = 1 } end,
    },
    ['lbf-show-to-others'] = {
        get = function(data) return data.flags.show_others end,
        set = function(data, value) data.flags.show_others = value end,
    },
}
State.player_settings = PLAYER_SETTINGS

-- Per-player mod setting each behavior flag mirrors (relative-gui / remote API, §8).
-- Shared so anything writing to data.flags[<flag>] can push the same setting
-- the relative-gui checkbox would have (State.push_setting).
State.flag_setting = {
    fuel = 'lbf-feed-fuel',
    ingredients = 'lbf-feed-ingredients',
    chests = 'lbf-take-chests',
    ground = 'lbf-pickup-ground',
    trash = 'lbf-drain-trash',
    summary = 'lbf-show-summary',
    show_others = 'lbf-show-to-others',
    rebalance = 'lbf-rebalance',
    starvation = 'lbf-show-starvation',
}

--- Read one per-player mod setting into storage (settings screen -> storage).
--- @param player LuaPlayer
--- @param name string
function State.pull_setting(player, name)
    local field = PLAYER_SETTINGS[name]
    if not field then
        return
    end
    field.set(State.get_player_data(player.index), settings.get_player_settings(player)[name].value)
end

--- Read every mirrored per-player mod setting into storage. Called on player
--- created/joined and when the mod is added to an existing save.
--- @param player LuaPlayer
function State.init_player(player)
    for name in pairs(PLAYER_SETTINGS) do
        State.pull_setting(player, name)
    end
end

--- Push one storage field out to its mirrored per-player mod setting (relative
--- GUI -> settings screen). No-op if already equal, so it never re-triggers
--- itself via on_runtime_mod_setting_changed.
--- @param player LuaPlayer
--- @param name string
--- @param a any
--- @param b any
--- @return boolean
local function setting_values_equal(a, b)
    if type(a) == 'table' and type(b) == 'table' then
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
    end
    return a == b
end

function State.push_setting(player, name)
    local field = PLAYER_SETTINGS[name]
    if not field then
        return
    end
    local value = field.get(State.get_player_data(player.index))
    local player_settings = settings.get_player_settings(player)
    if not setting_values_equal(player_settings[name].value, value) then
        player_settings[name] = { value = value }
    end
end

--- @param player_index uint
--- @param channel LbfChannel
--- @return boolean
function State.effective(player_index, channel)
    local data = State.get_player_data(player_index)
    return storage.active[channel] and not data.locked[channel] and data.enabled[channel]
end

--- @param player_index uint
--- @return boolean
function State.any_effective(player_index)
    for _, channel in pairs(State.channels) do
        if State.effective(player_index, channel) then
            return true
        end
    end
    return false
end

--- @return boolean
function State.any_master()
    for _, channel in pairs(State.channels) do
        if storage.active[channel] then
            return true
        end
    end
    return false
end

--- @param channel LbfChannel
--- @param value boolean
function State.set_master(channel, value)
    storage.active[channel] = value
    -- Re-enabling any retired master re-arms the SPM watchdog (DESIGN.md §2.1).
    if value then
        storage.auto_disabled = false
        storage.spm_strikes = 0
    end
end

--- @param value boolean
function State.set_all_masters(value)
    for _, channel in pairs(State.channels) do
        storage.active[channel] = value
    end
    if value then
        storage.auto_disabled = false
        storage.spm_strikes = 0
    end
end

--- @param player LuaPlayer
--- @param channel LbfChannel
--- @param value boolean
function State.set_player_enabled(player, channel, value)
    State.get_player_data(player.index).enabled[channel] = value
end

--- Admin per-player, per-channel lock. Locked = the channel is off for that
--- player no matter what they choose (§2).
--- @param player_index uint
--- @param channel LbfChannel
--- @param locked boolean
function State.set_locked(player_index, channel, locked)
    State.get_player_data(player_index).locked[channel] = locked
end

--- @param radius number
--- @return integer
function State.clamp_radius(radius)
    local min = settings.global['lbf-min-radius'].value --[[@as integer]]
    local max = settings.global['lbf-max-radius'].value --[[@as integer]]
    return math.max(min, math.min(max, math.floor(radius)))
end

--- @param player_index uint
--- @return integer
function State.get_radius(player_index)
    return State.clamp_radius(State.get_player_data(player_index).radius)
end

--- Single write path for radius: storage first, then the per-player mod setting
--- (which echoes back through on_runtime_mod_setting_changed, idempotently).
--- @param player LuaPlayer
--- @param radius number
function State.set_radius(player, radius)
    State.get_player_data(player.index).radius = State.clamp_radius(radius)
    State.push_setting(player, 'lbf-radius')
end

return State
