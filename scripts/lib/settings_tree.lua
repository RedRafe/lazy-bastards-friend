--- Generic hierarchical settings tree: a small, reusable class with no
--- LBF-specific knowledge beyond the tree definition passed to `.new`.
---
--- Each node has a global layer (`{ enabled }`, admin bulk switch) and a
--- per-player layer (`{ enabled, allowed }` — the player's own preference and
--- whether an admin allows it). A node is *effective* for a player iff every
--- node from the root down to it, inclusive, has global.enabled AND
--- player.enabled AND player.allowed. Writes never cascade: setting a parent
--- only gates descendants' effective state, it never touches their stored
--- values (DESIGN.md §2 — masters don't touch prefs).
---
--- Inspired by RedMew's danger_ores `configuration.lua` (one declarative table
--- of features, each with an `enabled` flag) extended with the admin-lock and
--- parent/child gating this mod needs.

local SettingsTree = {}
SettingsTree.__index = SettingsTree

--- @class LbfSettingsNodeDef
--- @field id string unique across the whole tree
--- @field setting string? mirrored mod-setting name, if any
--- @field children LbfSettingsNodeDef[]?

--- @class LbfSettingsNode
--- @field id string
--- @field setting string?
--- @field parent LbfSettingsNode?
--- @field children LbfSettingsNode[]

--- @param def LbfSettingsNodeDef[] top-level node definitions (forest of roots)
--- @return table
function SettingsTree.new(def)
    local self = setmetatable({}, SettingsTree)
    --- @type table<string, LbfSettingsNode>
    self.by_id = {}
    --- @type LbfSettingsNode[]
    self.roots = {}

    local function build(node_def, parent)
        if self.by_id[node_def.id] then
            error('settings_tree: duplicate node id "' .. node_def.id .. '"')
        end
        --- @type LbfSettingsNode
        local node = { id = node_def.id, setting = node_def.setting, parent = parent, children = {} }
        self.by_id[node.id] = node
        for _, child_def in pairs(node_def.children or {}) do
            node.children[#node.children + 1] = build(child_def, node)
        end
        return node
    end

    for _, root_def in pairs(def) do
        self.roots[#self.roots + 1] = build(root_def, nil)
    end
    return self
end

--- @param id string
--- @return LbfSettingsNode
function SettingsTree:node(id)
    local node = self.by_id[id]
    if not node then
        error('settings_tree: unknown node id "' .. tostring(id) .. '"')
    end
    return node
end

--- @param id string
--- @return LbfSettingsNode[] direct children, empty if none
function SettingsTree:children(id)
    return self:node(id).children
end

--- Ancestors from the node itself up to its root, inclusive.
--- @param id string
--- @return LbfSettingsNode[]
function SettingsTree:chain(id)
    local chain = {}
    local node = self:node(id)
    while node do
        chain[#chain + 1] = node
        node = node.parent
    end
    return chain
end

--- Idempotent default seeding for the global (admin) layer.
--- @param global table<string, {enabled: boolean}> e.g. storage.settings
function SettingsTree:init_global(global)
    for id in pairs(self.by_id) do
        if global[id] == nil then
            global[id] = { enabled = true }
        end
    end
end

--- Idempotent default seeding for one player's layer.
--- @param player table<string, {enabled: boolean, allowed: boolean}> e.g. data.settings
function SettingsTree:init_player(player)
    for id in pairs(self.by_id) do
        if player[id] == nil then
            player[id] = { enabled = true, allowed = true }
        end
    end
end

--- @param global table<string, {enabled: boolean}>
--- @param player table<string, {enabled: boolean, allowed: boolean}>
--- @param id string
--- @return boolean
function SettingsTree:effective(global, player, id)
    for _, node in pairs(self:chain(id)) do
        local g = global[node.id]
        local p = player[node.id]
        if not (g and g.enabled and p and p.enabled and p.allowed) then
            return false
        end
    end
    return true
end

--- Whether `id` can be toggled by its own player at all right now, i.e.
--- ignoring every ancestor's (and its own) *player* preference — a player can
--- always edit their own prefs, even ones that currently have no effect
--- because something above them is off (DESIGN.md §2: a player's own toggles
--- never grey their own children, only admin-side controls do). Only the
--- global (admin bulk) switch and the admin lock, at any level from the root
--- down to `id` inclusive, can make this false. Checked root-down, so a
--- master-level block is reported before a more specific one closer to `id`.
--- @param global table<string, {enabled: boolean}>
--- @param player table<string, {enabled: boolean, allowed: boolean}>
--- @param id string
--- @return LbfSettingsNode? node
--- @return ('global'|'allowed')? reason
function SettingsTree:admin_blocked(global, player, id)
    local chain = self:chain(id)
    for i = #chain, 1, -1 do
        local node = chain[i]
        local g = global[node.id]
        local p = player[node.id]
        if not (g and g.enabled) then
            return node, 'global'
        elseif not (p and p.allowed) then
            return node, 'allowed'
        end
    end
    return nil
end

--- @param player table<string, {enabled: boolean, allowed: boolean}>
--- @param id string
--- @param value boolean
function SettingsTree:set_enabled(player, id, value)
    self:node(id) -- validates id
    player[id].enabled = value
end

--- @param player table<string, {enabled: boolean, allowed: boolean}>
--- @param id string
--- @param value boolean
function SettingsTree:set_allowed(player, id, value)
    self:node(id) -- validates id
    player[id].allowed = value
end

--- @param global table<string, {enabled: boolean}>
--- @param id string
--- @param value boolean
function SettingsTree:set_global_enabled(global, id, value)
    self:node(id) -- validates id
    global[id].enabled = value
end

return SettingsTree
