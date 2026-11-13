-- WezTerm — ThinkPad P15 / T14s / GNOME Wayland
-- Match kitty/ghostty rice

local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.font = wezterm.font({
  family = "JetBrainsMono Nerd Font",
  harfbuzz_features = { "calt=0", "clig=0", "liga=0", "dlig=0" },
})
config.font_size = 13.0
config.line_height = 1.0

config.color_scheme = nil
config.window_background_opacity = 0.95
config.window_decorations = "TITLE | RESIZE"
config.window_padding = {
  left = 12,
  right = 12,
  top = 8,
  bottom = 8,
}
config.initial_cols = 120
config.initial_rows = 34

config.scrollback_lines = 50000
config.enable_scroll_bar = false
config.hide_mouse_cursor_when_typing = true

config.default_cursor_style = "BlinkingBlock"
config.cursor_blink_rate = 500
config.cursor_blink_ease_in = "Constant"
config.cursor_blink_ease_out = "Constant"

config.audible_bell = "Disabled"
config.visual_bell = {
  fade_in_duration_ms = 0,
  fade_out_duration_ms = 0,
}

config.enable_wayland = true
-- OpenGL more reliable on hybrid Intel/NVIDIA than WebGpu here
config.front_end = "OpenGL"

config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false

config.keys = {
  { key = "c", mods = "CTRL|SHIFT", action = wezterm.action.CopyTo("Clipboard") },
  { key = "v", mods = "CTRL|SHIFT", action = wezterm.action.PasteFrom("Clipboard") },
  { key = "=", mods = "CTRL|SHIFT", action = wezterm.action.IncreaseFontSize },
  { key = "-", mods = "CTRL|SHIFT", action = wezterm.action.DecreaseFontSize },
  { key = "0", mods = "CTRL|SHIFT", action = wezterm.action.ResetFontSize },
  { key = "t", mods = "CTRL|SHIFT", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "CTRL|SHIFT", action = wezterm.action.CloseCurrentTab({ confirm = false }) },
  { key = "n", mods = "CTRL|SHIFT", action = wezterm.action.SpawnWindow },
  {
    key = "d",
    mods = "CTRL|SHIFT",
    action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }),
  },
  {
    key = "e",
    mods = "CTRL|SHIFT",
    action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }),
  },
}

return config
