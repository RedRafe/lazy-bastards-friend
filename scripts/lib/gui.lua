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

--- Adds a draggable titlebar flow: an optional caption label, a stretching
--- drag handle, and an optional close button — the pattern shared by every
--- screen-anchored frame (admin panel, test-results panel).
--- @param frame LuaGuiElement frame the titlebar belongs to and drags
--- @param options { name: string?, label_name: string?, caption: LocalisedString?, close_tags: table? }?
--- @return LuaGuiElement titlebar
--- @return LuaGuiElement label
function Gui.add_titlebar(frame, options)
    options = options or {}
    local titlebar = frame.add({ type = 'flow', name = options.name or 'titlebar', direction = 'horizontal' })
    titlebar.drag_target = frame
    local label = titlebar.add({
        type = 'label',
        name = options.label_name,
        caption = options.caption,
        style = 'frame_title',
        ignored_by_interaction = true,
    })
    Gui.set_style(titlebar.add({ type = 'empty-widget', style = 'draggable_space_header', ignored_by_interaction = true }), {
        horizontally_stretchable = true,
        height = 24,
    })
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

return Gui
