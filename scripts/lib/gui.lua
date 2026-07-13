--- Small, commonly reused GUI building blocks shared by scripts/gui/ and
--- scripts/tests/lib/gui.lua. Kept dependency-free (no State/storage access)
--- so it can be required from any stage-appropriate module.

local Gui = {}

--- Applies a style to a LuaGuiElement in one call, instead of a chain of
--- `element.style.x = y` lines (inspired by RedMew's utils/gui.lua Gui.set_style).
--- A string sets the style prototype; a table sets individual LuaStyle attributes.
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

--- Adds a titlebar flow: an optional caption label, a stretching drag handle,
--- and an optional close button — the pattern shared by every screen-anchored
--- frame (admin panel, test-results panel). Pass `draggable = false` for
--- frames anchored in `player.gui.relative`/`.top` etc — `drag_target` is only
--- valid on frames living in `player.gui.screen` and errors otherwise.
--- @param frame LuaGuiElement frame the titlebar belongs to (and drags, unless draggable = false)
--- @param options { name: string?, label_name: string?, caption: LocalisedString?, close_tags: table?, draggable: boolean? }?
--- @return LuaGuiElement titlebar
--- @return LuaGuiElement label
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
        Gui.set_style(titlebar.add({ type = 'empty-widget', style = 'draggable_space_header', ignored_by_interaction = true }), {
            horizontally_stretchable = true,
            height = 24,
        })
    end
    if options.close_tags then
        titlebar.add({
            type = 'sprite-button',
            style = 'frame_action_button',
            sprite = 'utility/close',
            tags = options.close_tags,
        })
    end
    return titlebar, label
end

--- Adds the padded "content" frame every top-level panel nests its widgets in.
--- @param parent LuaGuiElement
--- @param style string? defaults to 'inside_shallow_frame_with_padding'
--- @return LuaGuiElement
function Gui.add_content_frame(parent, style)
    return parent.add({
        type = 'frame',
        name = 'content',
        style = style or 'inside_shallow_frame_with_padding',
        direction = 'vertical',
    })
end

--- Adds a flexible, stretching spacer — mirrors RedMew's utils.gui `add_pusher`.
--- @param element LuaGuiElement
--- @return LuaGuiElement
function Gui.add_pusher(element)
    return Gui.set_style(element.add({ type = 'empty-widget' }), { horizontally_stretchable = true })
end

--- Adds a collapsible section: a `subheader_frame` header (caption + an
--- expand/collapse arrow) sitting above a body flow the caller fills in and
--- whose visibility the arrow controls. Expand state is not tracked here —
--- the caller owns and persists it (per-player UI prefs), and drives the
--- arrow sprite / body visibility itself on sync.
--- @param parent LuaGuiElement
--- @param id string unique section id; elements are named 'lbf-section-<id>' and nested 'header'/'body'
--- @param caption LocalisedString
--- @param tags table tags applied to the arrow button (must route a click to the caller's dispatcher)
--- @param tooltip LocalisedString? shown on the caption label
--- @return LuaGuiElement outer the 'lbf-section-<id>' frame (index into it for sync)
--- @return LuaGuiElement body the vertical flow for section content
function Gui.add_collapsible(parent, id, caption, tags, tooltip)
    local outer = parent.add({ type = 'frame', name = 'lbf-section-' .. id, style = 'inside_shallow_frame', direction = 'vertical' })
    local header = Gui.set_style(outer.add({ type = 'frame', name = 'header', style = 'subheader_frame' }), { horizontally_stretchable = true })
    local header_flow = Gui.set_style(header.add({ type = 'flow', name = 'header-flow', direction = 'horizontal' }), {
        vertical_align = 'center',
        horizontally_stretchable = true,
    })
    header_flow.add({ type = 'label', name = 'label', caption = caption, tooltip = tooltip, style = 'subheader_caption_label' })
    Gui.add_pusher(header_flow)
    header_flow.add({
        type = 'sprite-button',
        name = 'arrow',
        style = 'frame_action_button',
        sprite = 'utility/collapse',
        tags = tags,
    })
    local body = Gui.set_style(outer.add({ type = 'flow', name = 'body', direction = 'vertical' }), {
        padding = 8,
        vertical_spacing = 4,
    })
    return outer, body
end

return Gui
