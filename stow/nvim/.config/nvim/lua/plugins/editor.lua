-- ============================================================
-- lua/plugins/editor.lua
-- Treesitter, Telescope, Git, Flash, mini, etc.
-- ============================================================
return {

  -- ── Treesitter (nvim 0.12 rewrite API) ─────────────────────
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
      "nvim-treesitter/nvim-treesitter-context",
      "windwp/nvim-ts-autotag",
      "HiPhish/rainbow-delimiters.nvim",
    },
    config = function()
      local parsers = {
        "astro", "bash", "css", "dockerfile", "fish",
        "gitcommit", "gitignore", "go", "gomod", "gosum",
        "html", "javascript", "jsdoc", "json",
        "lua", "luadoc", "make", "markdown", "markdown_inline",
        "python", "regex", "rust", "sql", "toml",
        "tsx", "typescript", "vim", "vimdoc", "yaml",
      }
      require("nvim-treesitter").setup({
        highlight = { enable = true },
      })
      if vim.fn.argc() == 0 then
        require("nvim-treesitter").install(parsers)
      end
    end,
  },

  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = {
          lookahead = true,
          keymaps = {
            ["af"] = "@function.outer", ["if"] = "@function.inner",
            ["ac"] = "@class.outer", ["ic"] = "@class.inner",
            ["aa"] = "@parameter.outer", ["ia"] = "@parameter.inner",
            ["ai"] = "@conditional.outer", ["ii"] = "@conditional.inner",
            ["al"] = "@loop.outer", ["il"] = "@loop.inner",
            ["ab"] = "@block.outer", ["ib"] = "@block.inner",
          },
        },
        move = {
          enable = true,
          set_jumps = true,
          goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer" },
          goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer" },
          goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer" },
          goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer" },
        },
        swap = {
          enable = true,
          swap_next = { ["<leader>a"] = "@parameter.inner" },
          swap_previous = { ["<leader>A"] = "@parameter.inner" },
        },
      })
    end,
  },

  {
    "windwp/nvim-ts-autotag",
    event = "InsertEnter",
    opts = {},
  },

  -- Treesitter context (shows function/class at top of window)
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = "BufReadPost",
    opts  = { max_lines = 3, mode = "cursor" },
    keys  = {
      { "<leader>ut", "<cmd>TSContextToggle<cr>", desc = "Toggle TS context" },
    },
  },

  -- ── Telescope ──────────────────────────────────────────────
  {
    "nvim-telescope/telescope.nvim",
    cmd          = "Telescope",
    version      = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
      "nvim-telescope/telescope-ui-select.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>",              desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",               desc = "Live grep" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>",                desc = "Recent files" },
      { "<leader>fb", "<cmd>Telescope buffers sort_mru=true<cr>",   desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>",               desc = "Help" },
      { "<leader>fk", "<cmd>Telescope keymaps<cr>",                 desc = "Keymaps" },
      { "<leader>fc", "<cmd>Telescope command_history<cr>",         desc = "Command history" },
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<cr>",    desc = "Document symbols" },
      { "<leader>fS", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>", desc = "Workspace symbols" },
      { "<leader>fd", "<cmd>Telescope diagnostics bufnr=0<cr>",     desc = "Buffer diagnostics" },
      { "<leader>fD", "<cmd>Telescope diagnostics<cr>",             desc = "Workspace diagnostics" },
      { "<leader>fw", "<cmd>Telescope grep_string<cr>",             desc = "Word under cursor" },
      { "<leader>gc", "<cmd>Telescope git_commits<cr>",             desc = "Git commits" },
      { "<leader>gs", "<cmd>Telescope git_status<cr>",              desc = "Git status" },
      { "<leader>gb", "<cmd>Telescope git_branches<cr>",            desc = "Git branches" },
      { "<leader>/",  "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Search buffer" },
      { "<leader>:",  "<cmd>Telescope command_history<cr>",         desc = "Command history" },
      { "<C-p>",      "<cmd>Telescope find_files<cr>",              desc = "Find files" },
    },
    config = function()
      local telescope = require("telescope")
      local actions   = require("telescope.actions")
      telescope.setup({
        defaults = {
          prompt_prefix   = "   ",
          selection_caret = " ",
          entry_prefix    = "  ",
          sorting_strategy = "ascending",
          layout_config   = {
            horizontal = { prompt_position = "top", preview_width = 0.55 },
            vertical   = { mirror = false },
            width      = 0.87, height = 0.80, preview_cutoff = 120,
          },
          file_ignore_patterns = { "node_modules", ".git/", "dist/", ".next/", ".astro/" },
          mappings = {
            i = {
              ["<C-n>"]    = actions.cycle_history_next,
              ["<C-p>"]    = actions.cycle_history_prev,
              ["<C-j>"]    = actions.move_selection_next,
              ["<C-k>"]    = actions.move_selection_previous,
              ["<C-q>"]    = actions.send_selected_to_qflist + actions.open_qflist,
              ["<esc>"]    = actions.close,
            },
          },
        },
        extensions = {
          fzf = { fuzzy = true, override_generic_sorter = true, override_file_sorter = true },
          ["ui-select"] = { require("telescope.themes").get_dropdown() },
        },
      })
      telescope.load_extension("fzf")
      telescope.load_extension("ui-select")
    end,
  },

  -- ── Git ────────────────────────────────────────────────────
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts  = {
      signs = {
        add          = { text = "▎" },
        change       = { text = "▎" },
        delete       = { text = "" },
        topdelete    = { text = "" },
        changedelete = { text = "▎" },
        untracked    = { text = "▎" },
      },
      on_attach = function(buffer)
        local gs = package.loaded.gitsigns
        local map = function(mode, l, r, desc)
          vim.keymap.set(mode, l, r, { buffer = buffer, desc = desc })
        end
        -- Navigation
        map("n", "]h", gs.next_hunk,           "Next hunk")
        map("n", "[h", gs.prev_hunk,           "Prev hunk")
        -- Actions
        map({ "n", "v" }, "<leader>ghs", "<cmd>Gitsigns stage_hunk<cr>",  "Stage hunk")
        map({ "n", "v" }, "<leader>ghr", "<cmd>Gitsigns reset_hunk<cr>",  "Reset hunk")
        map("n", "<leader>ghS", gs.stage_buffer,                          "Stage buffer")
        map("n", "<leader>ghu", gs.undo_stage_hunk,                       "Undo stage hunk")
        map("n", "<leader>ghR", gs.reset_buffer,                          "Reset buffer")
        map("n", "<leader>ghp", gs.preview_hunk,                          "Preview hunk")
        map("n", "<leader>ghb", function() gs.blame_line({ full = true }) end, "Blame line")
        map("n", "<leader>ghd", gs.diffthis,                              "Diff this")
        map("n", "<leader>ghD", function() gs.diffthis("~") end,          "Diff this ~")
        map("n", "<leader>tb",  gs.toggle_current_line_blame,             "Toggle blame")
        -- Text object
        map({ "o", "x" }, "ih", "<cmd>Gitsigns select_hunk<cr>", "Select hunk")
      end,
    },
  },

  {
    "sindrets/diffview.nvim",
    cmd  = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
    keys = {
      { "<leader>gd",  "<cmd>DiffviewOpen<cr>",          desc = "DiffView open" },
      { "<leader>gD",  "<cmd>DiffviewClose<cr>",         desc = "DiffView close" },
      { "<leader>gh",  "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
      { "<leader>gH",  "<cmd>DiffviewFileHistory<cr>",   desc = "Branch history" },
    },
    opts = {},
  },

  {
    "knubie/vim-kitty-navigator",
    event = "VeryLazy",
    init = function()
      vim.g.kitty_navigator_no_mappings = 1
    end,
  },

  -- ── Flash (fast navigation) ────────────────────────────────
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts  = {},
    keys  = {
      { "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
      { "S",     mode = { "n", "x", "o" }, function() require("flash").treesitter() end,        desc = "Flash treesitter" },
      { "r",     mode = "o",               function() require("flash").remote() end,             desc = "Remote flash" },
      { "R",     mode = { "x", "o" },      function() require("flash").treesitter_search() end, desc = "Treesitter search" },
      { "<c-s>", mode = "c",               function() require("flash").toggle() end,             desc = "Toggle flash search" },
    },
  },

  -- ── Surround ───────────────────────────────────────────────
  {
    "kylechui/nvim-surround",
    version = "*",
    event   = "VeryLazy",
    opts    = {},
  },

  -- ── Comments ───────────────────────────────────────────────
  {
    "folke/ts-comments.nvim",
    event   = "VeryLazy",
    opts    = {},
  },

  -- ── Autopairs ──────────────────────────────────────────────
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts  = { check_ts = true, ts_config = { lua = { "string" } } },
  },

  -- ── Mini utilities ─────────────────────────────────────────
  {
    "echasnovski/mini.nvim",
    version = false,
    event   = "VeryLazy",
    config  = function()
      require("mini.ai").setup({ n_lines = 500 })   -- better text objects
      require("mini.bufremove").setup()              -- better buffer close
      require("mini.pairs").setup()                  -- fallback autopairs
      require("mini.move").setup()                   -- move selection with Alt+arrows
    end,
  },

  -- ── inc-rename ─────────────────────────────────────────────
  {
    "smjonas/inc-rename.nvim",
    cmd  = "IncRename",
    keys = {
      { "<leader>cR", function()
          return ":IncRename " .. vim.fn.expand("<cword>")
        end, expr = true, desc = "Rename (incremental)" },
    },
    opts = {},
  },

  -- ── Todo comments ──────────────────────────────────────────
  {
    "folke/todo-comments.nvim",
    cmd  = { "TodoTrouble", "TodoTelescope" },
    event = "BufReadPost",
    keys = {
      { "]t",         function() require("todo-comments").jump_next() end, desc = "Next todo" },
      { "[t",         function() require("todo-comments").jump_prev() end, desc = "Prev todo" },
      { "<leader>ft", "<cmd>TodoTelescope<cr>", desc = "Find todos" },
      { "<leader>xt", "<cmd>TodoTrouble<cr>",   desc = "Todos (Trouble)" },
    },
    opts = {},
  },

  -- ── Render markdown ────────────────────────────────────────
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft           = { "markdown", "Avante" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts         = { file_types = { "markdown", "Avante" } },
  },
}
