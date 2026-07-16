--- Area-of-effect rendering (DESIGN.md §5). Render objects target the character
--- entity so the engine moves them for free — no per-tick Lua. Objects are destroyed
--- and recreated on any state/appearance change; color-only changes mutate in place.

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
    data.render = {}
end

--- Premultiply rgb by alpha, as the rendering API expects for translucency.
--- @param player LuaPlayer
--- @param data LbfPlayerData
--- @param alpha double
--- @return Color
local function resolve_color(player, data, alpha)
    local base = data.use_player_color and player.color or data.color
    return { r = base.r * alpha, g = base.g * alpha, b = base.b * alpha, a = alpha }
end

--- Destroy and (if any channel is effective and an anchor exists) redraw the
--- AoE. Registered as a State refresh handler. The anchor is the character —
--- targeting it makes the engine move the render every tick for free, no
--- per-tick Lua.
--- @param player LuaPlayer
function Rendering.refresh(player)
    local data = State.get_player_data(player.index)
    destroy(data)

    -- fill=false hides the area entirely (edge included); opacity is kept for
    -- when it's re-enabled.
    if not player.connected or not State.effective(player.index, 'appearance_fill') or not State.any_effective(player.index) then
        return
    end
    local anchor = player.character
    if not anchor then
        return
    end

    local radius = State.get_radius(player.index)
    local surface = anchor.surface
    local players = nil -- visible to everyone
    if not State.effective(player.index, 'appearance_show_others') then
        players = { player.index }
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

-- Starvation feedback (DESIGN.md §10.10): short-lived icons over machines
-- that wanted an item the player couldn't spare (starved) or that are
-- already full (saturated). time_to_live self-cleans — no storage bookkeeping.
local STARVATION_TICKS = 180
local STARVED_TINT = { r = 1, g = 0.3, b = 0.3, a = 1 }
local SATURATED_TINT = { r = 0.3, g = 1, b = 0.3, a = 1 }

--- @param player LuaPlayer
--- @param starved LuaEntity[]
--- @param saturated LuaEntity[]
function Rendering.flash_starvation(player, starved, saturated)
    for _, entity in pairs(starved) do
        if entity.valid then
            rendering.draw_sprite({
                sprite = 'utility/warning_icon',
                tint = STARVED_TINT,
                target = entity,
                surface = entity.surface,
                players = { player.index },
                time_to_live = STARVATION_TICKS,
                render_layer = 'entity-info-icon',
            })
        end
    end
    for _, entity in pairs(saturated) do
        if entity.valid then
            rendering.draw_sprite({
                sprite = 'utility/check_mark_white',
                tint = SATURATED_TINT,
                target = entity,
                surface = entity.surface,
                players = { player.index },
                time_to_live = STARVATION_TICKS,
                render_layer = 'entity-info-icon',
            })
        end
    end
end

--- Cheap in-place recolor for on_player_color_changed (no destroy/recreate).
--- @param player LuaPlayer
function Rendering.on_color_changed(player)
    local data = State.get_player_data(player.index)
    if not data.use_player_color then
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
