local wezterm = require("wezterm")

return {
	-- Font settings
	font = wezterm.font("CaskaydiaMono Nerd Font Mono", { weight = "DemiLight", stretch = "Normal", style = "Normal" }),
	font_size = 14,
	--font_antialias = "Subpixel",

	-- Scrollbar visible
	enable_scroll_bar = true,

	-- Unlimited scrollback / set to 100000 lines
	scrollback_lines = 100000,

	-- Additional UI tweaks (optional but usually good)
	enable_tab_bar = true,
	hide_tab_bar_if_only_one_tab = true,
	window_background_opacity = 1.0,

	-- Terminal behavior
	adjust_window_size_when_changing_font_size = false,

	color_scheme_dirs = { os.getenv("HOME") .. "/.local/share/iTerm2-color-schemes/wezterm" },
	--color_scheme = "GitLab Dark Grey",
	--color_scheme = "C64",
	color_scheme = "Citruszest",
	--color_scheme = "Dark Modern",
}
