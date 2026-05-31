-- ============================================================
-- lua/plugins/ui.lua
-- ============================================================
return {

  -- ── Statusline ─────────────────────────────────────────────
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = function()
      local icons = {
        diagnostics = {
          Error = " ", Warn = " ", Hint = " ", Info = " ",
        },
        git = { branch = " " },
      }
      return {
        options = {
          theme                = "catppuccin",
          globalstatus         = true,
          disabled_filetypes   = { statusline = { "dashboard", "alpha" } },
          component_separators = { left = "", right = "" },
          section_separators  = { left = "", right = "" },
        },
        sections = {
          lualine_a = { { "mode", icon = "" } },
          lualine_b = {
            { "branch", icon = icons.git.branch },
            {
              "diff",
              symbols = { added = " ", modified = " ", removed = " " },
            },
          },
          lualine_c = {
            { "filetype", icon_only = true, separator = "", padding = { left = 1, right = 0 } },
            { "filename", path = 1, symbols = { modified = " ●", readonly = " ", unnamed = "" } },
          },
          lualine_x = {
            {
              "diagnostics",
              symbols = icons.diagnostics,
            },
            { "encoding", cond = function() return vim.opt.fileencoding:get() ~= "utf-8" end },
            { "fileformat", symbols = { unix = " ", dos = " ", mac = " " } },
          },
          lualine_y = {
            { "progress", separator = " ", padding = { left = 1, right = 0 } },
            { "location", padding = { left = 0, right = 1 } },
          },
          lualine_z = {
            function()
              return " " .. os.date("%H:%M")
            end,
          },
        },
        extensions = { "neo-tree", "lazy", "mason", "trouble", "fugitive" },
      }
    end,
  },

  -- ── Buffer tabs ────────────────────────────────────────────
  {
    "akinsho/bufferline.nvim",
    event        = "VeryLazy",
    version      = "*",
    dependencies = "nvim-tree/nvim-web-devicons",
    keys = {
      { "<leader>bp", "<cmd>BufferLineTogglePin<cr>",            desc = "Pin buffer" },
      { "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<cr>", desc = "Close unpinned" },
    },
    opts = {
      options = {
        close_command       = "bdelete! %d",
        right_mouse_command = "bdelete! %d",
        diagnostics         = "nvim_lsp",
        diagnostics_indicator = function(_, _, diag)
          local icons = { error = " ", warning = " " }
          local ret = (diag.error and icons.error .. diag.error .. " " or "")
            .. (diag.warning and icons.warning .. diag.warning or "")
          return vim.trim(ret)
        end,
        always_show_bufferline = false,
        offsets = {
          { filetype = "neo-tree", text = "Files", highlight = "Directory", text_align = "center" },
        },
      },
    },
  },

  -- ── File explorer ──────────────────────────────────────────
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch       = "v3.x",
    cmd          = "Neotree",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>e",  "<cmd>Neotree toggle<cr>",                    desc = "Explorer" },
      { "<leader>E",  "<cmd>Neotree reveal<cr>",                    desc = "Reveal in explorer" },
      { "<leader>ge", "<cmd>Neotree source=git_status toggle<cr>",  desc = "Git explorer" },
    },
    opts = {
      sources = { "filesystem", "buffers", "git_status", "document_symbols" },
      open_files_do_not_replace_types = { "terminal", "Trouble", "trouble", "qf", "edgy" },
      filesystem = {
        bind_to_cwd      = false,
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        filtered_items = {
          visible        = false,
          hide_dotfiles  = false,
          hide_gitignored = true,
        },
      },
      window = {
        mappings = {
          ["<space>"] = "none",
          ["Y"]       = {
            function(state)
              local node = state.tree:get_node()
              local path = node:get_id()
              vim.fn.setreg("+", path, "c")
            end,
            desc = "Copy path to clipboard",
          },
        },
      },
      default_component_configs = {
        indent = {
          with_expanders = true,
          expander_collapsed = "",
          expander_expanded  = "",
        },
        git_status = {
          symbols = {
            added    = "✚", modified = "", deleted = "✖",
            renamed  = "󰁕", untracked = "", ignored  = "",
            unstaged = "󰄱", staged    = "", conflict  = "",
          },
        },
      },
    },
  },

  -- ── Notifications / cmdline ────────────────────────────────
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = { "MunifTanjim/nui.nvim", "rcarriga/nvim-notify" },
    keys = {
      { "<leader>sn",  function() require("noice").cmd("history") end, desc = "Noice history" },
      { "<S-Enter>",   function() require("noice").redirect(vim.fn.getcmdline()) end,
        mode = "c", desc = "Redirect cmdline" },
    },
    opts = {
      lsp = {
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"]   = true,
        },
      },
      routes = {
        { filter = { event = "msg_show", any = {
          { find = "%d+L, %d+B" }, { find = "; after #%d+" },
          { find = "; before #%d+" },
        }}, view = "mini" },
      },
      presets = {
        bottom_search         = true,
        command_palette       = true,
        long_message_to_split = true,
        inc_rename            = true,
      },
    },
  },

  -- ── Which-key ──────────────────────────────────────────────
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      plugins = { spelling = true },
      defaults = {},
      spec = {
        { "<leader>b",  group = "buffers",   icon = { icon = "󰓩", color = "cyan" } },
        { "<leader>c",  group = "code",      icon = { icon = "", color = "orange" } },
        { "<leader>d",  group = "debug",     icon = { icon = "", color = "red" } },
        { "<leader>f",  group = "find",      icon = { icon = "󰍉", color = "yellow" } },
        { "<leader>g",  group = "git",       icon = { icon = "󰊢", color = "green" } },
        { "<leader>r",  group = "refactor",  icon = { icon = "", color = "cyan" } },
        { "<leader>s",  group = "search",    icon = { icon = "󰍉", color = "yellow" } },
        { "<leader>t",  group = "test/term", icon = { icon = "", color = "green" } },
        { "<leader>u",  group = "ui",        icon = { icon = "󰙵", color = "cyan" } },
        { "<leader>x",  group = "diagnostics/qf", icon = { icon = "󱖫", color = "green" } },
        { "[",          group = "prev" },
        { "]",          group = "next" },
        { "g",          group = "goto" },
      },
    },
  },

  -- ── Indent guides ──────────────────────────────────────────
  {
    "lukas-reineke/indent-blankline.nvim",
    main  = "ibl",
    event = "BufReadPost",
    opts  = {
      indent  = { char = "│", tab_char = "│" },
      scope   = { enabled = false },
      exclude = {
        filetypes = { "help", "alpha", "dashboard", "neo-tree",
          "lazy", "mason", "notify", "toggleterm" },
      },
    },
  },

  {
    "echasnovski/mini.indentscope",
    version = false,
    event   = "BufReadPost",
    opts    = {
      symbol  = "│",
      options = { try_as_border = true },
    },
    init = function()
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "help", "alpha", "dashboard", "neo-tree", "lazy",
          "mason", "notify", "toggleterm" },
        callback = function() vim.b.miniindentscope_disable = true end,
      })
    end,
  },

  -- ── Dashboard ──────────────────────────────────────────────
  {
    "nvimdev/dashboard-nvim",
    event        = "VimEnter",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      theme = "hyper",
      config = {
        week_header = { enable = true },
        shortcut = {
          { desc = " Update",  group = "@property", action = "Lazy update",           key = "u" },
          { desc = " Files",   group = "Label",     action = "Telescope find_files",  key = "f" },
          { desc = " Recent",  group = "Label",     action = "Telescope oldfiles",    key = "r" },
          { desc = " Config",  group = "Label",     action = "e ~/.config/nvim/init.lua", key = "c" },
          { desc = " Quit",    group = "DiagnosticError", action = "qa",              key = "q" },
        },
      },
    },
  },

  -- ── UFO folding ────────────────────────────────────────────
  {
    "kevinhwang91/nvim-ufo",
    event        = "BufReadPost",
    dependencies = { "kevinhwang91/promise-async" },
    keys = {
      { "zR", function() require("ufo").openAllFolds() end,  desc = "Open all folds" },
      { "zM", function() require("ufo").closeAllFolds() end, desc = "Close all folds" },
      { "zK", function()
          local winid = require("ufo").peekFoldedLinesUnderCursor()
          if not winid then vim.lsp.buf.hover() end
        end, desc = "Peek fold" },
    },
    opts = {
      provider_selector = function(_, ft, _)
        local map = {
          typescript   = { "lsp", "indent" },
          typescriptreact = { "lsp", "indent" },
          javascript   = { "lsp", "indent" },
          javascriptreact = { "lsp", "indent" },
          astro        = { "lsp", "indent" },
          rust         = { "lsp", "indent" },
          go           = { "lsp", "indent" },
          python       = { "lsp", "indent" },
          lua          = { "lsp", "indent" },
        }
        return map[ft] or { "treesitter", "indent" }
      end,
    },
  },

  -- ── Scrollbar ──────────────────────────────────────────────
  {
    "lewis6991/satellite.nvim",
    event = "BufReadPost",
    opts  = {
      current_only = true,
      winblend     = 50,
      handlers     = {
        cursor    = { enable = true },
        search    = { enable = true },
        diagnostic = { enable = true, signs = { "-", "=", "≡" } },
        gitsigns  = { enable = true },
        marks     = { enable = false },
      },
    },
  },

  -- ── Zen mode ───────────────────────────────────────────────
  {
    "folke/zen-mode.nvim",
    cmd  = "ZenMode",
    keys = { { "<leader>z", "<cmd>ZenMode<cr>", desc = "Zen mode" } },
    opts = { window = { width = 100 } },
  },
}
