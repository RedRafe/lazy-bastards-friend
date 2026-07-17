--- Storage schema, per-player data access, and the settings-tree-backed
--- activation model. See DESIGN.md §2, §8, §9 and scripts/lib/settings_tree.lua
--- for the generic hierarchy engine this module configures.

local SettingsTree = require('__lazy-bastards-friend__.scripts.lib.settings_tree')

local State = {}

--- @alias LbfChannel 'collect'|'feed'|'appearance'

--- @type LbfChannel[]
-- Order matches the relative GUI's Feed/Take row order (relative.lua's
-- BEHAVIOR_GROUPS) so the admin player table's columns line up with it.
State.channels = { 'feed', 'collect', 'appearance' }

--- The settings tree: 'mod' is the whole-mod master (mirrors the toolbar
--- shortcut and the `lbf-enabled` setting). 'collect'/'feed'/'appearance' are
--- the three admin-lockable channels (own global master + per-player lock,
--- `State.channels`, admin GUI player table); their children are the
--- fine-grained behavior/appearance flags gated by them at runtime. Child ids
--- carry their family's prefix (`feed_fuel`, `collect_chests`,
--- `appearance_fill`, …) — both for internal clarity and because these ids
--- are also the public remote-API flag names (`set_player_flag`/
--- `get_player_state`, docs/API.md); the GUI strips the prefix back off to
--- reuse the existing unprefixed locale keys (§4.2, `relative.lua`'s
--- `locale_suffix`).
---
--- 'combat' is a true child of 'feed' (DESIGN.md §12) with no admin lock/
--- master of its own (2026-07-16, "vertical" refactor): turret feeding is
--- fully absorbed into Feed — it's just another per-player preference in
--- Feed's advanced list now (like `feed_fuel`), not a channel. It no longer
--- has a `State.channels` entry or a dedicated admin-GUI column; admins gate
--- it only indirectly via Feed's own master/lock. Still exposed remotely, but
--- through `set_player_flag`/`get_player_state.flags` like any other flag,
--- not `set_active`/`lock_player`.
---
--- 'appearance' replaces the old inert umbrella node of the same name,
--- promoted to a real channel (own global master + per-player lock, third
--- `State.channels` slot, replacing 'combat's admin-GUI column; briefly
--- called 'renders' internally before this rename, later that same day --
--- see DESIGN.md §12): its `setting` is the former `appearance_fill` node
--- ("Fill area" -- DESIGN.md §9 flagged this as the future "gate rendering
--- as a whole" hook), so the existing per-player Fill checkbox doubles as
--- this channel's own preference. 'appearance_starvation' and
--- 'appearance_show_others_area' are now its children -- turning the
--- 'appearance' channel off *for everyone* (admin) hides all AoE areas and
--- starvation icons regardless of individual prefs (destructive); leaving it
--- on is non-destructive -- each player's own opt-in (`appearance_fill`,
--- `appearance_show_others_area`, `appearance_starvation`) still applies as
--- before.
local TREE_DEF = {
    {
        id = 'mod',
        setting = 'lbf-enabled',
        children = {
            {
                id = 'collect',
                children = {
                    { id = 'collect_chests', setting = 'lbf-collect-chests' },
                    { id = 'collect_ground', setting = 'lbf-collect-ground' },
                },
            },
            {
                id = 'feed',
                children = {
                    { id = 'feed_fuel', setting = 'lbf-feed-fuel' },
                    { id = 'feed_ingredients', setting = 'lbf-feed-ingredients' },
                    { id = 'feed_trash', setting = 'lbf-drain-trash' },
                    { id = 'feed_rebalance', setting = 'lbf-rebalance' },
                    { id = 'combat' },
                },
            },
            {
                id = 'appearance',
                setting = 'lbf-fill-area',
                children = {
                    { id = 'appearance_show_others_area', setting = 'lbf-show-others-area' },
                    { id = 'appearance_starvation', setting = 'lbf-show-starvation' },
                },
            },
        },
    },
}

--- @type table
local Tree = SettingsTree.new(TREE_DEF)
State.tree = Tree

-- setting name -> tree node id, for every node that mirrors a mod setting.
local BOOL_SETTING_NODE = {}
for id, node in pairs(Tree.by_id) do
    if node.setting then
        BOOL_SETTING_NODE[node.setting] = id
    end
end

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
    storage.settings = storage.settings or {}
    Tree:init_global(storage.settings)

    storage.auto_disabled = storage.auto_disabled or false
    storage.spm_strikes = storage.spm_strikes or 0
    storage.scheduler = storage.scheduler or { queue = {}, cursor = 1 }
    storage.admin_guis = storage.admin_guis or {}
    storage.players = storage.players or {}
    storage.items_moved = storage.items_moved or 0

    for _, data in pairs(storage.players) do
        data.settings = data.settings or {}
        Tree:init_player(data.settings)
        if data.summary_enabled == nil then
            data.summary_enabled = false
        end
        data.summary = data.summary or { collected = {}, fed = {}, next_flush = 0 }
        data.excluded = data.excluded or {}
        data.ui = data.ui or State.default_ui()
        for id, default in pairs(State.default_ui().sections) do
            if data.ui.sections[id] == nil then
                data.ui.sections[id] = default
            end
        end
        for name in pairs(data.reserves) do
            if not prototypes.item[name] then
                data.reserves[name] = nil
            end
        end
    end
end

--- @class LbfPlayerData
--- @field settings table<string, {enabled: boolean, allowed: boolean}> settings-tree state (channels, behavior flags, appearance toggles)
--- @field radius uint
--- @field shape 'circle'|'square'
--- @field use_player_color boolean
--- @field color Color
--- @field opacity double
--- @field summary_enabled boolean flying-text transfer summary toggle (ungated — see DESIGN.md §12)
--- @field reserves table<string, uint>
--- @field excluded table<uint, boolean> unit_number -> excluded from this player's raids (§10.4)
--- @field cache {key: string, tick: uint, x: double, y: double, entities: LuaEntity[]}?
--- @field render {edge: LuaRenderObject?, fill: LuaRenderObject?}
--- @field idle uint
--- @field gui_version uint
--- @field summary {collected: table<string, integer>, fed: table<string, integer>, next_flush: uint}
--- @field ui {open: boolean, sections: table<string, boolean>} relative-gui prefs: whether the panel is expanded from its button, and which collapsible sections are open

--- Default relative-gui layout prefs for a brand new player: panel starts
--- collapsed to its button; once opened, only Behavior is expanded (the common
--- case — deciding what to feed/collect), everything else starts collapsed to
--- keep the panel small. 'feed'/'collect' are the advanced-options expanders
--- inside Behavior.
--- @return {open: boolean, sections: table<string, boolean>}
function State.default_ui()
    return {
        open = false,
        sections = {
            behavior = true,
            feed = false,
            collect = false,
            appearance = false,
            reserves = false,
        },
    }
end

--- @param player_index uint
--- @return LbfPlayerData
function State.get_player_data(player_index)
    local data = storage.players[player_index]
    if not data then
        data = {
            settings = {},
            radius = 16,
            shape = 'circle',
            use_player_color = true,
            color = { r = 1, g = 0.5, b = 0, a = 1 },
            opacity = 0.08,
            summary_enabled = false,
            reserves = {},
            excluded = {},
            render = {},
            idle = 0,
            gui_version = 0,
            summary = { collected = {}, fed = {}, next_flush = 0 },
            ui = State.default_ui(),
        }
        Tree:init_player(data.settings)
        storage.players[player_index] = data
    end
    return data
end

--- Per-player mod settings kept in sync with storage (DESIGN.md §8): every
--- boolean tree node that declares a `setting` mirrors it both ways
--- automatically; a handful of value-type appearance fields (not tree nodes —
--- "enabled" doesn't apply to a slider/color) are mirrored explicitly below.
--- @type table<string, {get: fun(data: LbfPlayerData): any, set: fun(data: LbfPlayerData, value: any)}>
local VALUE_SETTINGS = {
    ['lbf-radius'] = {
        get = function(data) return data.radius end,
        set = function(data, value) data.radius = State.clamp_radius(value) end,
    },
    ['lbf-shape'] = {
        get = function(data) return data.shape end,
        set = function(data, value) data.shape = value == 'square' and 'square' or 'circle' end,
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
    ['lbf-show-summary'] = {
        get = function(data) return data.summary_enabled end,
        set = function(data, value) data.summary_enabled = value end,
    },
}

-- Every mirrored per-player mod setting name, boolean tree nodes and value
-- fields alike — control.lua's on_runtime_mod_setting_changed uses this to
-- recognize which settings belong to State.pull_setting at all.
--- @type table<string, boolean>
State.player_settings = {}
for name in pairs(BOOL_SETTING_NODE) do
    State.player_settings[name] = true
end
for name in pairs(VALUE_SETTINGS) do
    State.player_settings[name] = true
end

--- Read one per-player mod setting into storage (settings screen -> storage).
--- @param player LuaPlayer
--- @param name string
function State.pull_setting(player, name)
    local value = settings.get_player_settings(player)[name].value
    local node_id = BOOL_SETTING_NODE[name]
    if node_id then
        Tree:set_enabled(State.get_player_data(player.index).settings, node_id, value == true)
        return
    end
    local field = VALUE_SETTINGS[name]
    if field then
        field.set(State.get_player_data(player.index), value)
    end
end

--- Read every mirrored per-player mod setting into storage. Called on player
--- created/joined and when the mod is added to an existing save.
--- @param player LuaPlayer
function State.init_player(player)
    for name in pairs(BOOL_SETTING_NODE) do
        State.pull_setting(player, name)
    end
    for name in pairs(VALUE_SETTINGS) do
        State.pull_setting(player, name)
    end
end

--- Push one storage field out to its mirrored per-player mod setting (relative
--- GUI -> settings screen). No-op if already equal, so it never re-triggers
--- itself via on_runtime_mod_setting_changed.
--- @param a any
--- @param b any
--- @return boolean
local function setting_values_equal(a, b)
    if type(a) == 'table' and type(b) == 'table' then
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
    end
    return a == b
end

--- @param player LuaPlayer
--- @param name string
function State.push_setting(player, name)
    local data = State.get_player_data(player.index)
    local value
    local node_id = BOOL_SETTING_NODE[name]
    if node_id then
        value = data.settings[node_id].enabled
    else
        local field = VALUE_SETTINGS[name]
        if not field then
            return
        end
        value = field.get(data)
    end
    local player_settings = settings.get_player_settings(player)
    if not setting_values_equal(player_settings[name].value, value) then
        player_settings[name] = { value = value }
    end
end

--- @param player_index uint
--- @param id string tree node id (channel or behavior/appearance flag)
--- @return boolean
function State.effective(player_index, id)
    local data = State.get_player_data(player_index)
    return Tree:effective(storage.settings, data.settings, id)
end

-- The channels that actually move items (scheduler/rendering "is there any
-- reason to service/draw this player" gate). 'appearance' is presentation-only —
-- a player with appearance on but collect+feed both off/locked has nothing to
-- show and no work to schedule, so it's deliberately excluded here even
-- though it's a full channel in `State.channels` (admin GUI/remote API).
--- @type LbfChannel[]
local WORK_CHANNELS = { 'collect', 'feed' }

--- @param player_index uint
--- @return boolean
function State.any_effective(player_index)
    for _, channel in pairs(WORK_CHANNELS) do
        if State.effective(player_index, channel) then
            return true
        end
    end
    return false
end

--- @return boolean
function State.any_master()
    if not storage.settings.mod.enabled then
        return false
    end
    for _, channel in pairs(WORK_CHANNELS) do
        if storage.settings[channel].enabled then
            return true
        end
    end
    return false
end

--- Global whole-mod switch — the admin GUI's "Everyone" On/Off. Preserves the
--- channel masters and every per-player setting; does not touch the watchdog.
--- @param value boolean
function State.set_global_master(value)
    Tree:set_global_enabled(storage.settings, 'mod', value)
end

--- Global masters no longer touch the watchdog: re-enabling a channel for
--- everyone must not re-arm a tripped watchdog (it would just retire again).
--- Re-arming is the watchdog switch's job — Watchdog.set_enabled (§2.1).
--- @param channel LbfChannel
--- @param value boolean
function State.set_master(channel, value)
    Tree:set_global_enabled(storage.settings, channel, value)
end

--- "All masters" = the global switch plus every channel master (the
--- singleplayer revive path in set_player_master).
--- @param value boolean
function State.set_all_masters(value)
    Tree:set_global_enabled(storage.settings, 'mod', value)
    for _, channel in pairs(State.channels) do
        Tree:set_global_enabled(storage.settings, channel, value)
    end
end

--- Single write path for any per-player tree node's own preference — the
--- channel checkboxes and every behavior/appearance flag all go through this
--- (replaces the old separate set_player_enabled/flag-write paths).
--- @param player LuaPlayer
--- @param id string
--- @param value boolean
function State.set_enabled(player, id, value)
    local data = State.get_player_data(player.index)
    Tree:set_enabled(data.settings, id, value)
    local node = Tree:node(id)
    if node.setting then
        State.push_setting(player, node.setting)
    end
end

--- Back-compat name for channel checkboxes (channels are just tree nodes now).
--- @param player LuaPlayer
--- @param channel LbfChannel
--- @param value boolean
function State.set_player_enabled(player, channel, value)
    State.set_enabled(player, channel, value)
end

--- Single write path for the per-player master switch (GUI switch and toolbar
--- shortcut — kept in sync through this). In singleplayer, an admin switching
--- on also re-arms the global masters, so the switch alone fully revives a
--- retired/disabled mod; in multiplayer the masters are admin-panel-only.
--- @param player LuaPlayer
--- @param value boolean
function State.set_player_master(player, value)
    State.set_enabled(player, 'mod', value)
    if value and player.admin and not game.is_multiplayer() then
        State.set_all_masters(true)
    end
end

--- Admin per-player lock for any tree node (channel or flag). Locked = the
--- node is off for that player no matter what they choose (§2).
--- @param player_index uint
--- @param id string
--- @param locked boolean
function State.set_locked(player_index, id, locked)
    Tree:set_allowed(State.get_player_data(player_index).settings, id, not locked)
end

--- Admin per-player master lock: the whole mod is off for that player no
--- matter what they choose, preserving all their prefs (§2).
--- @param player_index uint
--- @param locked boolean
function State.set_locked_master(player_index, locked)
    State.set_locked(player_index, 'mod', locked)
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
