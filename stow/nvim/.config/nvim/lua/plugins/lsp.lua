-- ============================================================
-- lua/plugins/lsp.lua
-- Mason + nvim-lspconfig + blink.cmp
-- Servers: tsserver, eslint, astro, rust-analyzer, gopls,
--          pyright, ruff, lua_ls, jsonls, taplo, tailwindcss
-- ============================================================
return {

  -- ── Mason: LSP/DAP/linter installer ────────────────────────
  {
    "williamboman/mason.nvim",
    cmd  = "Mason",
    keys = { { "<leader>cm", "<cmd>Mason<cr>", desc = "Mason" } },
    build = ":MasonUpdate",
    opts = {
      ui = { border = "rounded" },
      ensure_installed = {
        -- LSP
        "typescript-language-server",
        "astro-language-server",
        "rust-analyzer",
        "gopls",
        "pyright",
        "ruff",
        "lua-language-server",
        "json-lsp",
        "taplo",          -- TOML
        "tailwindcss-language-server",
        "css-lsp",
        "html-lsp",
        "marksman",       -- Markdown
        -- Formatters
        "prettier",
        "stylua",
        "gofumpt",
        "goimports",
        "black",
        "isort",
        -- Linters
        "eslint_d",
        "selene",         -- Lua linter
        -- DAP
        "js-debug-adapter",
        "delve",          -- Go debugger
        "debugpy",
      },
    },
    config = function(_, opts)
      require("mason").setup(opts)
      if not vim.fn.stdout_isatty() then
        return
      end
      local mr = require("mason-registry")
      mr.refresh(function()
        for _, tool in ipairs(opts.ensure_installed) do
          local p = mr.get_package(tool)
          if not p:is_installed() then p:install() end
        end
      end)
    end,
  },

  -- ── LSP config ─────────────────────────────────────────────
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "b0o/SchemaStore.nvim",       -- JSON schemas
      { "folke/lazydev.nvim", opts = {} },  -- nvim Lua API completion
    },
    config = function()
      -- Diagnostic signs
      local signs = {
        Error = " ", Warn = " ", Hint = " ", Info = " ",
      }
      vim.diagnostic.config({
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = signs.Error,
            [vim.diagnostic.severity.WARN] = signs.Warn,
            [vim.diagnostic.severity.HINT] = signs.Hint,
            [vim.diagnostic.severity.INFO] = signs.Info,
          },
        },
        underline       = true,
        update_in_insert = false,
        virtual_text = {
          spacing  = 4,
          source   = "if_many",
          prefix   = "●",
        },
        severity_sort   = true,
        float = {
          border  = "rounded",
          source  = "always",
        },
      })

      -- Shared on_attach
      local on_attach = function(client, bufnr)
        local map = function(keys, func, desc)
          vim.keymap.set("n", keys, func, { buffer = bufnr, desc = "LSP: " .. desc })
        end

        map("gd",         vim.lsp.buf.definition,       "Go to definition")
        map("gD",         vim.lsp.buf.declaration,      "Go to declaration")
        map("gi",         vim.lsp.buf.implementation,   "Go to implementation")
        map("gr",         require("telescope.builtin").lsp_references, "References")
        map("gt",         vim.lsp.buf.type_definition,  "Type definition")
        map("K",          vim.lsp.buf.hover,            "Hover docs")
        map("<C-k>",      vim.lsp.buf.signature_help,   "Signature help")
        map("<leader>ca", vim.lsp.buf.code_action,      "Code action")
        map("<leader>cr", vim.lsp.buf.rename,           "Rename")
        map("<leader>ci", "<cmd>LspInfo<cr>",           "LSP info")
        map("<leader>cl", vim.lsp.codelens.run,         "Run codelens")
        map("[d",         vim.diagnostic.goto_prev,     "Prev diagnostic")
        map("]d",         vim.diagnostic.goto_next,     "Next diagnostic")

        -- Inlay hints (nvim 0.10+)
        if client.supports_method("textDocument/inlayHint") then
          vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
          map("<leader>uh", function()
            vim.lsp.inlay_hint.enable(
              not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }),
              { bufnr = bufnr }
            )
          end, "Toggle inlay hints")
        end

        -- Highlight word under cursor
        if client.supports_method("textDocument/documentHighlight") then
          local hl_group = vim.api.nvim_create_augroup("lsp_doc_highlight", { clear = false })
          vim.api.nvim_clear_autocmds({ group = hl_group, buffer = bufnr })
          vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
            group = hl_group, buffer = bufnr,
            callback = vim.lsp.buf.document_highlight,
          })
          vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
            group = hl_group, buffer = bufnr,
            callback = vim.lsp.buf.clear_references,
          })
        end
      end

      -- Capabilities (extended by blink.cmp)
      local blink_ok, blink = pcall(require, "blink.cmp")
      local blink_caps = blink_ok and blink.get_lsp_capabilities and blink.get_lsp_capabilities()
        or vim.lsp.protocol.make_client_capabilities()
      local capabilities = vim.tbl_deep_extend(
        "force",
        vim.lsp.protocol.make_client_capabilities(),
        blink_caps or {}
      )
      capabilities.textDocument.foldingRange = {
        dynamicRegistration = false,
        lineFoldingOnly     = true,
      }

      -- Per-server configs
      local servers = {
        ts_ls = {
          settings = {
            typescript = {
              inlayHints = {
                includeInlayParameterNameHints    = "literals",
                includeInlayFunctionParameterTypeHints = true,
                includeInlayVariableTypeHints     = true,
                includeInlayPropertyDeclarationTypeHints = true,
                includeInlayFunctionLikeReturnTypeHints  = true,
              },
            },
          },
        },
        eslint = {
          settings = {
            workingDirectories = { mode = "auto" },
          },
          on_attach = function(_, bufnr)
            vim.api.nvim_create_autocmd("BufWritePre", {
              buffer   = bufnr,
              command  = "EslintFixAll",
            })
          end,
        },
        astro = {},
        tailwindcss = {
          filetypes_include = { "astro", "typescriptreact", "javascriptreact" },
        },
        rust_analyzer = {
          settings = {
            ["rust-analyzer"] = {
              cargo       = { allFeatures = true, loadOutDirsFromCheck = true },
              checkOnSave = { command = "clippy", extraArgs = { "--no-deps" } },
              procMacro   = { enable = true },
              inlayHints  = {
                bindingModeHints            = { enable = false },
                chainingHints               = { enable = true },
                closingBraceHints           = { enable = true, minLines = 25 },
                closureReturnTypeHints      = { enable = "with_block" },
                lifetimeElisionHints        = { enable = "skip_trivial" },
                parameterHints              = { enable = true },
                typeHints                   = { enable = true },
              },
            },
          },
        },
        gopls = {
          settings = {
            gopls = {
              gofumpt        = true,
              codelenses      = {
                gc_details     = false,
                generate       = true,
                regenerate_cgo = true,
                run_govulncheck = true,
                test           = true,
                tidy           = true,
                upgrade_dependency = true,
                vendor         = true,
              },
              hints = {
                assignVariableTypes    = true,
                compositeLiteralFields = true,
                compositeLiteralTypes  = true,
                constantValues         = true,
                functionTypeParameters = true,
                parameterNames         = true,
                rangeVariableTypes     = true,
              },
              analyses = {
                fieldalignment  = true,
                nilness         = true,
                unusedparams    = true,
                unusedwrite     = true,
                useany          = true,
              },
              usePlaceholders  = true,
              completeUnimported = true,
              staticcheck      = true,
              directoryFilters = { "-.git", "-.vscode", "-.idea",
                "-.yarn", "-node_modules" },
            },
          },
        },
        pyright = {
          settings = {
            python = {
              analysis = {
                typeCheckingMode     = "standard",
                autoImportCompletions = true,
              },
            },
          },
        },
        ruff = {
          on_attach = function(client, _)
            client.server_capabilities.hoverProvider = false
          end,
        },
        lua_ls = {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              codeLens  = { enable = true },
              completion = { callSnippet = "Replace" },
              hint = {
                enable        = true,
                setType       = false,
                paramType     = true,
                paramName     = "Disable",
                semicolon     = "Disable",
                arrayIndex    = "Disable",
              },
            },
          },
        },
        jsonls = {
          settings = {
            json = {
              schemas  = require("schemastore").json.schemas(),
              validate = { enable = true },
            },
          },
        },
        taplo = {},
        cssls = {},
        html  = {},
        marksman = {},
      }

      require("mason-lspconfig").setup({
        ensure_installed = vim.tbl_keys(servers),
        handlers = {
          function(server_name)
            local server = servers[server_name] or {}
            local srv_on_attach = server.on_attach
            server.on_attach = function(client, bufnr)
              on_attach(client, bufnr)
              if srv_on_attach then srv_on_attach(client, bufnr) end
            end
            server.capabilities = vim.tbl_deep_extend(
              "force", capabilities, server.capabilities or {}
            )
            require("lspconfig")[server_name].setup(server)
          end,
        },
      })
    end,
  },

  -- ── blink.cmp (faster than nvim-cmp) ───────────────────────
  {
    "saghen/blink.cmp",
    lazy         = false,
    version      = "*",
    dependencies = {
      "rafamadriz/friendly-snippets",
      "L3MON4D3/LuaSnip",
    },
    opts = {
      keymap = {
        preset = "default",
        ["<Tab>"]   = { "select_next", "fallback" },
        ["<S-Tab>"] = { "select_prev", "fallback" },
        ["<CR>"]    = { "accept", "fallback" },
        ["<C-e>"]   = { "cancel" },
        ["<C-b>"]   = { "scroll_documentation_up", "fallback" },
        ["<C-f>"]   = { "scroll_documentation_down", "fallback" },
        ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
      },
      appearance = {
        use_nvim_cmp_as_default = false,
        nerd_font_variant        = "mono",
      },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      cmdline = {
        sources = { "cmdline" },
      },
      completion = {
        accept     = { auto_brackets = { enabled = true } },
        menu = {
          border        = "rounded",
          draw = {
            treesitter = { "lsp" },
            columns    = {
              { "label", "label_description", gap = 1 },
              { "kind_icon", "kind", gap = 1 },
            },
          },
        },
        documentation = {
          auto_show         = true,
          auto_show_delay_ms = 100,
          window = { border = "rounded" },
        },
        ghost_text = { enabled = true },
      },
      snippets = {
        preset = "luasnip",
      },
    },
  },

  -- ── Formatter ──────────────────────────────────────────────
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd   = "ConformInfo",
    keys  = {
      { "<leader>cf", function() require("conform").format({ async = true, lsp_fallback = true }) end,
        desc = "Format buffer" },
    },
    opts = {
      formatters_by_ft = {
        lua            = { "stylua" },
        python         = { "isort", "black" },
        javascript     = { "prettier" },
        javascriptreact = { "prettier" },
        typescript     = { "prettier" },
        typescriptreact = { "prettier" },
        astro          = { "prettier" },
        css            = { "prettier" },
        html           = { "prettier" },
        json           = { "prettier" },
        jsonc          = { "prettier" },
        yaml           = { "prettier" },
        markdown       = { "prettier" },
        go             = { "goimports", "gofumpt" },
        rust           = { "rustfmt" },
        toml           = { "taplo" },
        sh             = { "shfmt" },
        bash           = { "shfmt" },
        zsh            = { "shfmt" },
      },
      format_on_save = {
        timeout_ms  = 3000,
        lsp_fallback = true,
      },
    },
  },

  -- ── Trouble (diagnostics) ──────────────────────────────────
  {
    "folke/trouble.nvim",
    cmd  = { "Trouble" },
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",
        desc = "Diagnostics (Trouble)" },
      { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
        desc = "Buffer diagnostics" },
      { "<leader>xL", "<cmd>Trouble loclist toggle<cr>",  desc = "Location list" },
      { "<leader>xQ", "<cmd>Trouble qflist toggle<cr>",   desc = "Quickfix list" },
      { "<leader>cs", "<cmd>Trouble symbols toggle<cr>",  desc = "Symbols" },
      { "<leader>cS", "<cmd>Trouble lsp toggle<cr>",      desc = "LSP definitions/references" },
    },
    opts = { use_diagnostic_signs = true },
  },

  -- ── Fidget (LSP progress) ──────────────────────────────────
  {
    "j-hui/fidget.nvim",
    event = "LspAttach",
    opts  = {
      notification = {
        window = { winblend = 0 },
      },
    },
  },
}
