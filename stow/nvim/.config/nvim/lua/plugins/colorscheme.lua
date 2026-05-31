-- ============================================================
-- lua/plugins/colorscheme.lua
-- ============================================================
return {
  {
    "catppuccin/nvim",
    name     = "catppuccin",
    priority = 1000,
    lazy     = false,
    opts = {
      flavour             = "mocha",
      background          = { light = "latte", dark = "mocha" },
      transparent_background = false,
      show_end_of_buffer  = false,
      term_colors         = true,
      dim_inactive        = { enabled = true, shade = "dark", percentage = 0.15 },
      styles = {
        comments    = { "italic" },
        conditionals = { "italic" },
        functions   = {},
        keywords    = { "italic" },
        strings     = {},
        variables   = {},
      },
      integrations = {
        blink_cmp          = true,
        cmp                = true,
        dap                = true,
        dap_ui             = true,
        diffview           = true,
        fidget             = true,
        flash              = true,
        fzf                = true,
        gitsigns           = true,
        indent_blankline   = { enabled = true, scope_color = "lavender" },
        lsp_saga           = false,
        lsp_trouble        = true,
        mason              = true,
        mini               = { enabled = true, indentscope_color = "lavender" },
        native_lsp = {
          enabled = true,
          virtual_text = {
            errors      = { "italic" },
            hints       = { "italic" },
            warnings    = { "italic" },
            information = { "italic" },
          },
          underlines = {
            errors      = { "underline" },
            hints       = { "underline" },
            warnings    = { "underline" },
            information = { "underline" },
          },
          inlay_hints = { background = true },
        },
        neotree            = true,
        noice              = true,
        notify             = true,
        rainbow_delimiters = true,
        render_markdown    = true,
        telescope          = { enabled = true, style = "nvchad" },
        treesitter         = true,
        treesitter_context = true,
        ufo                = true,
        which_key          = true,
      },
    },
    config = function(_, opts)
      require("catppuccin").setup(opts)
      vim.cmd("colorscheme catppuccin")
    end,
  },
}
