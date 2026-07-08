--- Per-player settings panel, anchored to the character screen (DESIGN.md §4.2).
--- Channel switches, behavior toggles, radius slider, appearance options and the
--- reserved-items editor with logistic-group import.
--- All interactions route through tags (element.tags.lbf_action), never element names.

local State = require('scripts.state')

local Gui = {}

-- Bump to force a destroy+rebuild of every player's panel on join/config change.
local GUI_VERSION = 3

local FRAME_NAME = 'lbf-relative'

-- Behavior toggles, in display order; each maps to data.flags[<flag>].
local BEHAVIOR_FLAGS = { 'fuel', 'ingredients', 'chests', 'ground', 'trash', 'summary' }

-- Logistic group whose minimum values the import button copies into reserves (§6).
local IMPORT_GROUP = 'LBF'

local COLOR_COMPONENTS = { 'r', 'g', 'b' }

--- @param player LuaPlayer
--- @return LuaGuiElement?
local function get_frame(player)
    return player.gui.relative[FRAME_NAME]
end

--- @param player LuaPlayer
function Gui.build(player)
    local existing = get_frame(player)
    if existing then
        existing.destroy()
    end

    local frame = player.gui.relative.add({
        type = 'frame',
        name = FRAME_NAME,
        direction = 'vertical',
        caption = { 'lbf-gui.title' },
        anchor = {
            gui = defines.relative_gui_type.controller_gui,
            position = defines.relative_gui_position.right,
        },
    })
    local content = frame.add({
        type = 'frame',
        name = 'content',
        style = 'inside_shallow_frame_with_padding',
        direction = 'vertical',
    })

    for _, channel in pairs(State.channels) do
        content.add({
            type = 'checkbox',
            name = 'lbf-channel-' .. channel,
            caption = { 'lbf-gui.channel-' .. channel },
            state = true,
            tags = { lbf_action = 'toggle-channel', channel = channel },
        })
    end

    content.add({ type = 'line', name = 'separator-behavior' })
    content.add({ type = 'label', name = 'behavior-label', caption = { 'lbf-gui.behavior' }, style = 'caption_label' })

    for _, flag in pairs(BEHAVIOR_FLAGS) do
        content.add({
            type = 'checkbox',
            name = 'lbf-flag-' .. flag,
            caption = { 'lbf-gui.flag-' .. flag },
            state = false,
            tags = { lbf_action = 'toggle-flag', flag = flag },
        })
    end

    local radius_flow = content.add({ type = 'flow', name = 'radius-flow', direction = 'horizontal' })
    radius_flow.style.vertical_align = 'center'
    radius_flow.add({ type = 'label', name = 'radius-label', caption = { 'lbf-gui.radius' }, tooltip = { 'lbf-gui.radius-tooltip' } })
    radius_flow.add({
        type = 'slider',
        name = 'lbf-radius-slider',
        minimum_value = 1,
        maximum_value = 100,
        value = 16,
        value_step = 1,
        tags = { lbf_action = 'radius-slider' },
    })
    radius_flow.add({ type = 'label', name = 'lbf-radius-value', caption = '16' })

    content.add({ type = 'line', name = 'separator-appearance' })
    content.add({ type = 'label', name = 'appearance-label', caption = { 'lbf-gui.appearance' }, style = 'caption_label' })

    local shape_flow = content.add({ type = 'flow', name = 'shape-flow', direction = 'horizontal' })
    shape_flow.style.vertical_align = 'center'
    shape_flow.add({ type = 'label', name = 'shape-label', caption = { 'lbf-gui.shape' } })
    shape_flow.add({
        type = 'drop-down',
        name = 'lbf-shape',
        items = { { 'lbf-gui.shape-circle' }, { 'lbf-gui.shape-square' } },
        selected_index = 1,
        tags = { lbf_action = 'shape' },
    })

    local fill_flow = content.add({ type = 'flow', name = 'fill-flow', direction = 'horizontal' })
    fill_flow.style.vertical_align = 'center'
    fill_flow.add({
        type = 'checkbox',
        name = 'lbf-fill',
        caption = { 'lbf-gui.fill' },
        tooltip = { 'lbf-gui.fill-tooltip' },
        state = true,
        tags = { lbf_action = 'fill' },
    })
    fill_flow.add({
        type = 'slider',
        name = 'lbf-opacity',
        minimum_value = 2,
        maximum_value = 50,
        value = 8,
        value_step = 1,
        tooltip = { 'lbf-gui.opacity-tooltip' },
        tags = { lbf_action = 'opacity' },
    })

    content.add({
        type = 'checkbox',
        name = 'lbf-use-player-color',
        caption = { 'lbf-gui.use-player-color' },
        state = true,
        tags = { lbf_action = 'use-player-color' },
    })

    local color_flow = content.add({ type = 'flow', name = 'color-flow', direction = 'vertical' })
    for _, component in pairs(COLOR_COMPONENTS) do
        local row = color_flow.add({ type = 'flow', name = 'row-' .. component, direction = 'horizontal' })
        row.style.vertical_align = 'center'
        row.add({ type = 'label', name = 'label', caption = { 'lbf-gui.color-' .. component } })
        row.add({
            type = 'slider',
            name = 'lbf-color-' .. component,
            minimum_value = 0,
            maximum_value = 255,
            value = 255,
            value_step = 1,
            tags = { lbf_action = 'color', component = component },
        })
    end

    content.add({
        type = 'checkbox',
        name = 'lbf-flag-show_others',
        caption = { 'lbf-gui.show-others' },
        tooltip = { 'lbf-gui.show-others-tooltip' },
        state = false,
        tags = { lbf_action = 'toggle-flag', flag = 'show_others' },
    })

    content.add({ type = 'line', name = 'separator-reserves' })

    local reserves_header = content.add({ type = 'flow', name = 'reserves-header', direction = 'horizontal' })
    reserves_header.style.vertical_align = 'center'
    reserves_header.add({
        type = 'label',
        name = 'reserves-label',
        caption = { 'lbf-gui.reserves' },
        tooltip = { 'lbf-gui.reserves-tooltip' },
        style = 'caption_label',
    })
    local spacer = reserves_header.add({ type = 'empty-widget', name = 'spacer' })
    spacer.style.horizontally_stretchable = true
    reserves_header.add({
        type = 'button',
        name = 'lbf-reserves-import',
        caption = { 'lbf-gui.reserves-import' },
        tooltip = { 'lbf-gui.reserves-import-tooltip' },
        tags = { lbf_action = 'reserve-import' },
    })

    content.add({ type = 'table', name = 'lbf-reserves', column_count = 3 })

    local add_flow = content.add({ type = 'flow', name = 'reserves-add-flow', direction = 'horizontal' })
    add_flow.style.vertical_align = 'center'
    add_flow.add({
        type = 'choose-elem-button',
        name = 'lbf-reserve-add',
        elem_type = 'item',
        tooltip = { 'lbf-gui.reserve-add-tooltip' },
        tags = { lbf_action = 'reserve-add' },
    })
    add_flow.add({ type = 'label', name = 'add-label', caption = { 'lbf-gui.reserve-add' } })

    -- Tagged for the admin dispatcher (scripts/gui/admin.lua), not ours.
    content.add({
        type = 'button',
        name = 'lbf-admin-open',
        caption = { 'lbf-gui.admin-open' },
        tooltip = { 'lbf-gui.admin-open-tooltip' },
        tags = { lbf_admin_action = 'toggle' },
    })

    State.get_player_data(player.index).gui_version = GUI_VERSION
    Gui.sync(player)
end

--- Rebuild only when missing or from an older schema (used on join/config change).
--- @param player LuaPlayer
function Gui.ensure(player)
    if not get_frame(player) or State.get_player_data(player.index).gui_version ~= GUI_VERSION then
        Gui.build(player)
    end
end

--- True when the rendered reserve rows show exactly the items in `reserves` —
--- counts may lag (they are only re-read on rebuild) but the set is what matters;
--- skipping the rebuild keeps a textfield being typed in alive.
--- @param grid LuaGuiElement
--- @param reserves table<string, uint>
--- @return boolean
local function reserve_rows_match(grid, reserves)
    local total = 0
    for _ in pairs(reserves) do
        total = total + 1
    end
    local children = grid.children
    if #children ~= total * 3 then
        return false
    end
    for i = 1, #children, 3 do
        local item = children[i].tags.item
        if not item or reserves[item] == nil then
            return false
        end
    end
    return true
end

--- @param grid LuaGuiElement
--- @param reserves table<string, uint>
local function sync_reserves(grid, reserves)
    if reserve_rows_match(grid, reserves) then
        return
    end
    grid.clear()
    local names = {}
    for name in pairs(reserves) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in pairs(names) do
        local icon = grid.add({
            type = 'sprite',
            sprite = 'item/' .. name,
            tooltip = prototypes.item[name].localised_name,
            tags = { item = name },
        })
        icon.style.width = 28
        icon.style.height = 28
        icon.style.stretch_image_to_widget_size = true
        local count = grid.add({
            type = 'textfield',
            text = tostring(reserves[name]),
            numeric = true,
            allow_decimal = false,
            allow_negative = false,
            tooltip = { 'lbf-gui.reserve-count-tooltip' },
            tags = { lbf_action = 'reserve-count', item = name },
        })
        count.style.width = 60
        grid.add({
            type = 'sprite-button',
            sprite = 'utility/trash',
            style = 'tool_button_red',
            tooltip = { 'lbf-gui.reserve-remove' },
            tags = { lbf_action = 'reserve-remove', item = name },
        })
    end
end

--- Push storage state into the panel: checkbox states, enabled/disabled with a
--- "why" tooltip, slider bounds and values, appearance widgets, reserve rows.
--- Registered as a State refresh handler.
--- @param player LuaPlayer
function Gui.sync(player)
    local frame = get_frame(player)
    if not frame then
        return
    end
    local content = frame.content
    local data = State.get_player_data(player.index)
    local flags = data.flags

    for _, channel in pairs(State.channels) do
        local checkbox = content['lbf-channel-' .. channel]
        checkbox.state = data.enabled[channel]
        if not storage.active[channel] then
            checkbox.enabled = false
            checkbox.tooltip = { 'lbf-gui.master-off' }
        elseif data.locked[channel] then
            checkbox.enabled = false
            checkbox.tooltip = { 'lbf-gui.locked-by-admin' }
        else
            checkbox.enabled = true
            checkbox.tooltip = { 'lbf-gui.channel-' .. channel .. '-tooltip' }
        end
    end

    for _, flag in pairs(BEHAVIOR_FLAGS) do
        local checkbox = content['lbf-flag-' .. flag]
        checkbox.state = flags[flag] == true
        checkbox.tooltip = { 'lbf-gui.flag-' .. flag .. '-tooltip' }
    end
    if settings.global['lbf-allow-chest-take'].value ~= true then
        local chests = content['lbf-flag-chests']
        chests.enabled = false
        chests.tooltip = { 'lbf-gui.flag-chests-forbidden' }
    else
        content['lbf-flag-chests'].enabled = true
    end

    content['lbf-admin-open'].visible = player.admin

    local radius = State.get_radius(player.index)
    local radius_flow = content['radius-flow']
    local slider = radius_flow['lbf-radius-slider']
    slider.set_slider_minimum_maximum(settings.global['lbf-min-radius'].value --[[@as number]], settings.global['lbf-max-radius'].value --[[@as number]])
    slider.slider_value = radius
    radius_flow['lbf-radius-value'].caption = tostring(radius)

    content['shape-flow']['lbf-shape'].selected_index = data.shape == 'square' and 2 or 1
    local fill_flow = content['fill-flow']
    fill_flow['lbf-fill'].state = data.fill
    fill_flow['lbf-opacity'].slider_value = math.floor(data.opacity * 100 + 0.5)
    fill_flow['lbf-opacity'].enabled = data.fill
    content['lbf-use-player-color'].state = data.use_player_color
    local color_flow = content['color-flow']
    color_flow.visible = not data.use_player_color
    for _, component in pairs(COLOR_COMPONENTS) do
        color_flow['row-' .. component]['lbf-color-' .. component].slider_value =
            math.floor((data.color[component] or 0) * 255 + 0.5)
    end
    content['lbf-flag-show_others'].state = flags.show_others == true

    sync_reserves(content['lbf-reserves'], data.reserves)
end

--- Copy minimum values from the player's logistic group named `LBF` into their
--- reserves (§6 — import-on-click only, no live sync).
--- @param player LuaPlayer
--- @param data LbfPlayerData
local function import_reserves(player, data)
    local character = player.character
    local sections = character and character.get_logistic_sections()
    local imported = 0
    if sections then
        for _, section in pairs(sections.sections) do
            if section.group == IMPORT_GROUP then
                for _, filter in pairs(section.filters) do
                    local value = filter.value
                    local name = value and (value.type == nil or value.type == 'item') and value.name
                    local min = filter.min or 0
                    if name and min > 0 and prototypes.item[name] then
                        data.reserves[name] = math.floor(min)
                        imported = imported + 1
                    end
                end
            end
        end
    end
    if imported > 0 then
        player.print({ 'lbf-message.import-done', imported, IMPORT_GROUP })
    else
        player.create_local_flying_text({
            text = { 'lbf-message.import-none', IMPORT_GROUP },
            create_at_cursor = true,
        })
    end
end

--- @param event EventData.on_gui_checked_state_changed|EventData.on_gui_value_changed|EventData.on_gui_click|EventData.on_gui_elem_changed|EventData.on_gui_text_changed|EventData.on_gui_selection_state_changed
function Gui.dispatch(event)
    local element = event.element
    if not (element and element.valid) then
        return
    end
    local tags = element.tags
    local action = tags and tags.lbf_action
    if not action then
        return
    end
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    local data = State.get_player_data(player.index)

    if action == 'toggle-channel' then
        State.set_player_enabled(player, tags.channel --[[@as LbfChannel]], element.state)
        State.refresh(player)
    elseif action == 'radius-slider' then
        State.set_radius(player, element.slider_value)
        State.refresh(player)
    elseif action == 'toggle-flag' then
        data.flags[tags.flag --[[@as string]]] = element.state
        State.refresh(player)
    elseif action == 'shape' then
        data.shape = element.selected_index == 2 and 'square' or 'circle'
        State.refresh(player)
    elseif action == 'fill' then
        data.fill = element.state
        State.refresh(player)
    elseif action == 'opacity' then
        data.opacity = element.slider_value / 100
        State.refresh(player)
    elseif action == 'use-player-color' then
        data.use_player_color = element.state
        State.refresh(player)
    elseif action == 'color' then
        data.color[tags.component --[[@as string]]] = element.slider_value / 255
        data.color.a = 1
        State.refresh(player)
    elseif action == 'reserve-add' then
        local name = element.elem_value --[[@as string?]]
        element.elem_value = nil
        if name and data.reserves[name] == nil then
            data.reserves[name] = prototypes.item[name].stack_size
            State.refresh(player)
        end
    elseif action == 'reserve-count' then
        -- Storage-only update: no refresh, or the rebuild would eat the
        -- textfield mid-typing. The value shown is already what was typed.
        local count = tonumber(element.text)
        if count and count >= 0 then
            data.reserves[tags.item --[[@as string]]] = math.floor(count)
        end
    elseif action == 'reserve-remove' then
        data.reserves[tags.item --[[@as string]]] = nil
        State.refresh(player)
    elseif action == 'reserve-import' then
        import_reserves(player, data)
        State.refresh(player)
    end
end

return Gui
