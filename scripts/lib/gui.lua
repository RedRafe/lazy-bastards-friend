--- Small, commonly reused GUI building blocks shared by scripts/gui/ and scripts/tests/lib/gui.lua. Kept dependency-free (no State/storage access) so it can be required from any stage-appropriate module. Recurring looks are lbf_* style prototypes (prototypes/styles.lua); set_style is for leftover one-off/dynamic tweaks.

local Gui = {}

--- Applies a style to a LuaGuiElement in one call instead of a chain of `element.style.x = y` lines (inspired by RedMew's utils/gui.lua Gui.set_style). A string sets the style prototype; a table sets individual LuaStyle attributes.
--- @param element LuaGuiElement
--- @param style string|table<string, any>
--- @return LuaGuiElement element, for chaining into the next add() call
function Gui.set_style(element, style)
    if type(style) == 'string' then
        element.style = style
        return element
    end
    local target = element.style
    for key, value in pairs(style) do
        target[key] = value
    end
    return element
end

--- Adds a titlebar flow (caption label, stretching drag handle, optional close button) — the pattern shared by every screen-anchored frame. Pass `draggable = false` for frames in `player.gui.relative`/`.top` etc — `drag_target` is only valid on `player.gui.screen` frames and errors otherwise.
--- @param frame LuaGuiElement frame the titlebar belongs to (and drags, unless draggable = false)
--- @param options { name: string?, label_name: string?, caption: LocalisedString?, close_tags: table?, close_tooltip: LocalisedString? draggable: boolean? }?
--- @return LuaGuiElement titlebar
--- @return LuaGuiElement label
--- @return LuaGuiElement? close_button
function Gui.add_titlebar(frame, options)
    options = options or {}
    local titlebar = frame.add({ type = 'flow', name = options.name or 'titlebar', direction = 'horizontal' })
    local label = titlebar.add({
        type = 'label',
        name = options.label_name,
        caption = options.caption,
        style = 'frame_title',
        ignored_by_interaction = true,
    })
    if options.draggable == false then
        Gui.add_pusher(titlebar)
    else
        titlebar.drag_target = frame
        titlebar.add({ type = 'empty-widget', style = 'lbf_drag_handle', ignored_by_interaction = true })
    end
    if options.close_tags or options.close_tooltip then
        titlebar.add({
            type = 'sprite-button',
            style = 'frame_action_button',
            sprite = 'utility/close',
            tags = options.close_tags,
            tooltip = options.close_tooltip,
        })
    end
    return titlebar, label
end

--- Adds a flexible, stretching spacer — mirrors RedMew's utils.gui `add_pusher`.
--- @param element LuaGuiElement
--- @return LuaGuiElement
function Gui.add_pusher(element)
    return element.add({ type = 'empty-widget', style = 'lbf_pusher' })
end

--- Builds an action-keyed GUI event dispatcher, replacing if/elseif cascades over `element.tags[key]` (inspired by reference/gui.lua's handler_factory, generalized across event types). Keys on tags rather than `element.name` since sibling elements often share a handler but not a name, and tags can carry per-row data too. `on(action, handler)` asserts against silent double-registration, which would otherwise just shadow the first handler.
--- @param key string tags field the action is read from (e.g. 'lbf_action')
--- @return function on function(action: string, handler: function(event, element, tags, player))
--- @return function dispatch function(event) — pass to `on(defines.events..., dispatch)`
function Gui.new_dispatcher(key)
    local handlers = {}

    local function on(action, handler)
        assert(not handlers[action], string.format('gui dispatcher(%s): handler already registered for action %q', key, action))
        handlers[action] = handler
    end

    local function dispatch(event)
        local element = event.element
        if not (element and element.valid) then
            return
        end
        local tags = element.tags
        local action = tags and tags[key]
        local handler = action and handlers[action]
        if not handler then
            return
        end
        local player = game.get_player(event.player_index)
        if not player then
            return
        end
        handler(event, element, tags, player)
    end

    return on, dispatch
end

--- Adds a collapsible section: a `subheader_frame` header (caption + expand/collapse arrow) above a body flow the caller fills in. Expand state isn't tracked here — the caller owns/persists it and drives arrow sprite / body visibility on sync.
--- @param parent LuaGuiElement
--- @param id string unique section id; elements are named 'lbf-section-<id>' and nested 'header'/'body'
--- @param caption LocalisedString
--- @param tags table tags applied to the arrow button (must route a click to the caller's dispatcher)
--- @param tooltip LocalisedString? shown on the caption label
--- @return LuaGuiElement outer the 'lbf-section-<id>' frame (index into it for sync)
--- @return LuaGuiElement body the vertical flow for section content
function Gui.add_collapsible(parent, id, caption, tags, tooltip)
    local outer = parent.add({ type = 'frame', name = 'lbf-section-' .. id, style = 'inside_shallow_frame', direction = 'vertical' })
    local header = outer.add({ type = 'frame', name = 'header', style = 'lbf_subheader_frame' })
    local header_flow = header.add({ type = 'flow', name = 'header-flow', direction = 'horizontal', style = 'lbf_subheader_flow' })
    header_flow.add({ type = 'label', name = 'label', caption = caption, tooltip = tooltip, style = 'subheader_caption_label' })
    Gui.add_pusher(header_flow)
    header_flow.add({
        type = 'sprite-button',
        name = 'arrow',
        style = 'frame_action_button',
        sprite = 'utility/collapse',
        tags = tags,
    })
    local body = outer.add({ type = 'flow', name = 'body', direction = 'vertical', style = 'lbf_section_body_flow' })
    return outer, body
end

--- Adds a "family section": a plain vertical flow (no frame of its own — avoids nested-frame dividers) holding an optional borderless header row (icon, caption, divider line, expand/collapse arrow) above an inside_shallow_frame body the caller fills in; collapsing hides the body-frame. `tags` applies to every header element so clicking anywhere on the header toggles the section, not just the arrow hitbox. Pass sprite = nil for a headerless section (just the body-frame, e.g. the top master-switch strip). Sibling of add_collapsible with the same contract (caller owns/persists expand state). Element tree: 'lbf-section-<id>' > 'header-flow'? (icon/label/line/arrow), 'body-frame' > 'body'.
--- @param parent LuaGuiElement must already be a frame — this doesn't add its own
--- @param id string unique section id; elements are named 'lbf-section-<id>' and nested 'header-flow'/'body-frame'
--- @param sprite string? family icon shown at the left of the header; omit (with caption/tags/tooltip) for no header
--- @param caption LocalisedString?
--- @param tags table? tags applied to every header element (must route a click to the caller's dispatcher)
--- @param tooltip LocalisedString? shown on the caption label
--- @return LuaGuiElement outer the 'lbf-section-<id>' flow (index into it for sync)
--- @return LuaGuiElement body the vertical flow for section content
function Gui.add_family_section(parent, id, sprite, caption, tags, tooltip)
    local outer = parent.add({ type = 'flow', name = 'lbf-section-' .. id, style = 'lbf_section_flow', direction = 'vertical' })
    if sprite then
        local header_flow = outer.add({ type = 'flow', name = 'header-flow', direction = 'horizontal', style = 'lbf_section_header_flow', tags = tags })
        header_flow.add({
            type = 'sprite-button',
            name = 'icon',
            style = 'lbf_section_icon_button',
            sprite = sprite,
            tags = tags,
        })
        header_flow.add({ type = 'label', name = 'label', caption = caption, tooltip = tooltip, style = 'lbf_section_caption_label', tags = tags })
        header_flow.add({ type = 'line', name = 'line', direction = 'horizontal', style = 'lbf_section_header_line', tags = tags })
        header_flow.add({
            type = 'sprite-button',
            name = 'arrow',
            style = 'lbf_section_arrow_button',
            sprite = 'utility/collapse',
            tags = tags,
        })
    end
    local body_frame = outer.add({ type = 'frame', name = 'body-frame', style = 'inside_shallow_frame', direction = 'vertical' })
    local body = body_frame.add({ type = 'flow', name = 'body', direction = 'vertical', style = 'lbf_section_body_flow' })
    return outer, body
end

return Gui
