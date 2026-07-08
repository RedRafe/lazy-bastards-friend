--- Area-of-effect rendering (DESIGN.md §5). Render objects target the character
--- entity so the engine moves them for free — no per-tick Lua. Objects are destroyed
--- and recreated on any state/appearance change; color-only changes mutate in place.

local State = require('scripts.state')

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

--- Destroy and (if any channel is effective and a character exists) redraw the AoE.
--- Registered as a State refresh handler.
--- @param player LuaPlayer
function Rendering.refresh(player)
    local data = State.get_player_data(player.index)
    destroy(data)

    if not player.connected or not State.any_effective(player.index) then
        return
    end
    local character = player.character
    if not character then
        return
    end

    local radius = State.get_radius(player.index)
    local surface = character.surface
    local players = nil -- visible to everyone
    if not data.flags.show_others then
        players = { player.index }
    end

    if data.shape == 'square' then
        local left_top = { entity = character, offset = { -radius, -radius } }
        local right_bottom = { entity = character, offset = { radius, radius } }
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
        if data.fill then
            data.render.fill = rendering.draw_rectangle({
                color = resolve_color(player, data, data.opacity),
                filled = true,
                left_top = left_top,
                right_bottom = right_bottom,
                surface = surface,
                players = players,
                draw_on_ground = true,
            })
        end
    else
        data.render.edge = rendering.draw_circle({
            color = resolve_color(player, data, EDGE_ALPHA),
            radius = radius,
            width = EDGE_WIDTH,
            filled = false,
            target = character,
            surface = surface,
            players = players,
            draw_on_ground = true,
        })
        if data.fill then
            data.render.fill = rendering.draw_circle({
                color = resolve_color(player, data, data.opacity),
                radius = radius,
                filled = true,
                target = character,
                surface = surface,
                players = players,
                draw_on_ground = true,
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
