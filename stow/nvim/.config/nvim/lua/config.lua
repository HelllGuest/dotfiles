-- extra configuration
local has_palette, palette = pcall(require, "palette")
if has_palette then
    -- Example: Set accent color for search results or cursor
    vim.api.nvim_set_hl(0, "Search", { bg = palette.accent, fg = palette.background })
end
