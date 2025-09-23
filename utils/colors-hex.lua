local colors = {
    red = 0xFF0000,
    red_dark = 0x990000,
    green = 0x00DB40,
    green_dark = 0x009200,
    blue = 0x0000FF,
    yellow = 0xFFDB00,
    orange = 0xFF6D00,
    black = 0x0,
    white = 0xFFFFFF,
    grey = 0x4B4B4B,
    grey_light = 0x787878,
    grey_dark = 0x2D2D2D
};

colors.background = colors.black;
colors.foreground = colors.white;

colors.primary = colors.grey;
colors.secondary = colors.grey_light;
colors.tertiary = colors.grey_dark;

colors.label = colors.foreground;
colors.border = colors.tertiary;

colors.loading = colors.yellow;
colors.success = colors.green;
colors.failure = colors.red;
colors.warning = colors.yellow;


return colors;