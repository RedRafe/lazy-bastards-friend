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
    storage.players = storage.players or {}
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
--- @field cache {key: string, tick: uint, x: double, y: double, entities: LuaEntity[]}?
--- @field render {edge: LuaRenderObject?, fill: LuaRenderObject?}
--- @field idle uint
--- @field gui_version uint

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
            flags = { fuel = true, ingredients = true, chests = false, ground = false, show_others = false },
            reserves = {},
            render = {},
            idle = 0,
            gui_version = 0,
        }
        storage.players[player_index] = data
    end
    return data
end

--- Pull per-player mod settings into storage. Called on player created/joined and
--- when the mod is added to an existing save.
--- @param player LuaPlayer
function State.init_player(player)
    local data = State.get_player_data(player.index)
    data.radius = State.clamp_radius(settings.get_player_settings(player)['lbf-radius'].value --[[@as integer]])
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
    local value = State.clamp_radius(radius)
    State.get_player_data(player.index).radius = value
    local player_settings = settings.get_player_settings(player)
    if player_settings['lbf-radius'].value ~= value then
        player_settings['lbf-radius'] = { value = value }
    end
end

return State
