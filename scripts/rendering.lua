--- Area-of-effect rendering. Render objects target the character entity so the engine moves them for free (no per-tick Lua); objects are destroyed and recreated on any state/appearance change, but color-only changes mutate in place.

local State = require('__lazy-bastards-friend__.scripts.state')

local Rendering = {}

local EDGE_ALPHA = 0.5
local EDGE_WIDTH = 3

--- @param data LbfPlayerData
local function destroy(data)
    local render = data.render
    if render.edge and render.edge.valid then
        render.edge.destroy()
    end
    if render.fill and render.fill.valid then
        render.fill.destroy()
    end
    if render.starvation then
        for _, obj in pairs(render.starvation) do
            if obj.valid then
                obj.destroy()
            end
        end
    end
    data.render = {}
end

--- Premultiply rgb by alpha, as the rendering API expects for translucency.
--- @param player LuaPlayer
--- @param data LbfPlayerData
--- @param alpha double
--- @return Color
local function resolve_color(player, data, alpha)
    local base = State.effective(player.index, 'appearance_use_player_color') and player.color or data.color
    return { r = base.r * alpha, g = base.g * alpha, b = base.b * alpha, a = alpha }
end

--- Destroy and (if any channel is effective and an anchor exists) redraw the AoE. Registered as a State refresh handler; the anchor is the character, so the engine moves the render every tick for free.
--- @param player LuaPlayer
function Rendering.refresh(player)
    local data = State.get_player_data(player.index)
    destroy(data)

    -- fill=false hides the area entirely (edge included); opacity is kept for when it's re-enabled.
    if not player.connected or not State.effective(player.index, 'appearance') or not State.any_effective(player.index) then
        return
    end
    local anchor = player.character
    if not anchor then
        return
    end

    local radius = State.get_radius(player.index)
    local surface = anchor.surface

    -- Visibility is viewer-opt-in, not owner-opt-out: the owner always sees their own area; others are added only if they've opted in to seeing others' areas. Connection status doesn't matter — an offline client renders nothing anyway, so join/leave never need to touch anyone else's whitelist.
    local players = { player.index }
    for _, viewer in pairs(game.players) do
        if viewer.index ~= player.index and State.effective(viewer.index, 'appearance_show_others_area') then
            players[#players + 1] = viewer.index
        end
    end

    if data.shape == 'square' then
        local left_top = { entity = anchor, offset = { -radius, -radius } }
        local right_bottom = { entity = anchor, offset = { radius, radius } }
        data.render.edge = rendering.draw_rectangle({
            color = resolve_color(player, data, EDGE_ALPHA),
            width = EDGE_WIDTH,
            filled = false,
            left_top = left_top,
            right_bottom = right_bottom,
            surface = surface,
            players = players,
            draw_on_ground = true,
        })
        data.render.fill = rendering.draw_rectangle({
            color = resolve_color(player, data, data.opacity),
            filled = true,
            left_top = left_top,
            right_bottom = right_bottom,
            surface = surface,
            players = players,
            draw_on_ground = true,
        })
    else
        data.render.edge = rendering.draw_circle({
            color = resolve_color(player, data, EDGE_ALPHA),
            radius = radius,
            width = EDGE_WIDTH,
            filled = false,
            target = anchor,
            surface = surface,
            players = players,
            draw_on_ground = true,
        })
        data.render.fill = rendering.draw_circle({
            color = resolve_color(player, data, data.opacity),
            radius = radius,
            filled = true,
            target = anchor,
            surface = surface,
            players = players,
            draw_on_ground = true,
        })
    end
end

-- Starvation feedback: a short-lived icon over machines that wanted an item the player couldn't spare. Tracked per-entity in data.render.starvation (rather than left to time_to_live alone) so a later icon for the same entity replaces rather than stacks on an earlier one, and so they can be force-cleared by destroy() (e.g. toggling LBF off) instead of lingering until they expire.
local STARVATION_TICKS = 180
local STARVATION_SCALE = 0.2 -- native icon is 64px (2 tiles at scale 1); shrink to well under one tile
local STARVATION_INSET = 0.2 -- tiles; half the rendered icon size, so it sits inside the corner rather than straddling it
local STARVED_TINT = { r = 1, g = 0.3, b = 0.3, a = 1 }

--- Offset from entity.position to its bounding box's bottom-right corner, pulled in by STARVATION_INSET.
--- @param entity LuaEntity
--- @return TilePosition
local function corner_offset(entity)
    local box = entity.bounding_box
    local pos = entity.position
    return {
        box.right_bottom.x - pos.x - STARVATION_INSET,
        box.right_bottom.y - pos.y - STARVATION_INSET,
    }
end

--- @param data LbfPlayerData
--- @param player LuaPlayer
--- @param entity LuaEntity
local function draw_starvation_icon(data, player, entity)
    data.render.starvation = data.render.starvation or {}
    local existing = data.render.starvation[entity.unit_number]
    if existing and existing.valid then
        existing.destroy()
    end
    data.render.starvation[entity.unit_number] = rendering.draw_sprite({
        sprite = 'utility/warning_icon',
        tint = STARVED_TINT,
        target = { entity = entity, offset = corner_offset(entity) },
        surface = entity.surface,
        players = { player.index },
        time_to_live = STARVATION_TICKS,
        x_scale = STARVATION_SCALE,
        y_scale = STARVATION_SCALE,
        render_layer = 'entity-info-icon',
    })
end

--- @param player LuaPlayer
--- @param starved LuaEntity[]
function Rendering.flash_starvation(player, starved)
    local data = State.get_player_data(player.index)
    for _, entity in pairs(starved) do
        if entity.valid then
            draw_starvation_icon(data, player, entity)
        end
    end
end

--- Cheap in-place recolor for on_player_color_changed (no destroy/recreate).
--- @param player LuaPlayer
function Rendering.on_color_changed(player)
    local data = State.get_player_data(player.index)
    if not State.effective(player.index, 'appearance_use_player_color') then
        return
    end
    local render = data.render
    if render.edge and render.edge.valid then
        render.edge.color = resolve_color(player, data, EDGE_ALPHA)
    end
    if render.fill and render.fill.valid then
        render.fill.color = resolve_color(player, data, data.opacity)
    end
end

--- Explicit cleanup before deleting player data (on_player_removed).
--- @param data LbfPlayerData
function Rendering.destroy(data)
    destroy(data)
end

return Rendering
