--- Applies a style to a LuaGuiElement in one call, instead of a chain of
--- `element.style.x = y` lines (inspired by RedMew's utils/gui.lua Gui.set_style).
--- A string sets the style prototype; a table sets individual LuaStyle attributes.
--- @param element LuaGuiElement
--- @param style string|table<string, any>
--- @return LuaGuiElement element, for chaining into the next add() call
local function set_style(element, style)
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

return set_style
