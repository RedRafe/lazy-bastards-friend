data:extend({
    {
        type = 'custom-input',
        name = 'lbf-toggle',
        key_sequence = 'CONTROL + SHIFT + L',
        action = 'lua',
    },
    {
        type = 'shortcut',
        name = 'lbf-toggle',
        action = 'lua',
        toggleable = true,
        associated_control_input = 'lbf-toggle',
        icon = '__base__/graphics/icons/coal.png',
        icon_size = 64,
        small_icon = '__base__/graphics/icons/coal.png',
        small_icon_size = 64,
        order = 'l[lbf]',
    },
    -- Invisible statistics item (DESIGN.md §10.5): the runtime pumps transferred
    -- counts into item production statistics under this name, so the mod's
    -- activity shows up in the vanilla production graphs (like base's 'science').
    {
        type = 'item',
        name = 'lbf-items-moved',
        icon = '__base__/graphics/icons/coal.png',
        icon_size = 64,
        subgroup = 'other',
        order = 'zz[lbf-items-moved]',
        hidden = true,
        hidden_in_factoriopedia = true,
        stack_size = 1,
    },
})
