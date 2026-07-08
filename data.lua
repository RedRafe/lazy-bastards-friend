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
})
