-- ============================================================
-- lua/plugins/dap.lua
-- Debug Adapter Protocol — JS/TS, Go, Python, Rust
-- ============================================================
return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
      "theHamsta/nvim-dap-virtual-text",
      "leoluz/nvim-dap-go",
      "mfussenegger/nvim-dap-python",
    },
    keys = {
      { "<leader>db",  function() require("dap").toggle_breakpoint() end,                   desc = "Breakpoint" },
      { "<leader>dB",  function() require("dap").set_breakpoint(vim.fn.input("Condition: ")) end, desc = "Conditional breakpoint" },
      { "<leader>dc",  function() require("dap").continue() end,                            desc = "Continue" },
      { "<leader>di",  function() require("dap").step_into() end,                           desc = "Step into" },
      { "<leader>do",  function() require("dap").step_over() end,                           desc = "Step over" },
      { "<leader>dO",  function() require("dap").step_out() end,                            desc = "Step out" },
      { "<leader>dr",  function() require("dap").run_last() end,                            desc = "Run last" },
      { "<leader>dt",  function() require("dap").terminate() end,                           desc = "Terminate" },
      { "<leader>du",  function() require("dapui").toggle() end,                            desc = "DAP UI" },
      { "<leader>de",  function() require("dapui").eval() end, mode = { "n", "v" },         desc = "Eval" },
    },
    config = function()
      local dap    = require("dap")
      local dapui  = require("dapui")

      -- ── DAP UI ─────────────────────────────────────────────
      dapui.setup({
        icons  = { expanded = "", collapsed = "", current_frame = "" },
        layouts = {
          {
            elements = {
              { id = "scopes",      size = 0.25 },
              { id = "breakpoints", size = 0.25 },
              { id = "stacks",      size = 0.25 },
              { id = "watches",     size = 0.25 },
            },
            size = 40, position = "left",
          },
          {
            elements = { { id = "repl", size = 0.5 }, { id = "console", size = 0.5 } },
            size = 15, position = "bottom",
          },
        },
      })

      -- Auto open/close dapui
      dap.listeners.after.event_initialized["dapui_config"]  = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"]  = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"]      = function() dapui.close() end

      -- ── Virtual text ───────────────────────────────────────
      require("nvim-dap-virtual-text").setup({
        commented  = true,
        virt_text_win_col = 80,
      })

      -- ── JS/TS (js-debug-adapter via Mason) ─────────────────
      local js_debug = vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js"
      for _, lang in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact" }) do
        dap.adapters[lang] = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = "node",
            args    = { js_debug, "${port}" },
          },
        }
        dap.configurations[lang] = {
          {
            type      = lang,
            request   = "launch",
            name      = "Launch file",
            program   = "${file}",
            cwd       = "${workspaceFolder}",
            sourceMaps = true,
            protocol  = "inspector",
          },
          {
            type      = lang,
            request   = "attach",
            name      = "Attach to process",
            processId = require("dap.utils").pick_process,
            cwd       = "${workspaceFolder}",
          },
        }
      end

      -- ── Go (delve) ─────────────────────────────────────────
      require("dap-go").setup({
        dap_configurations = {
          {
            type    = "go",
            name    = "Debug test (go.mod)",
            request = "launch",
            mode    = "test",
            program = "./${relativeFileDirname}",
          },
        },
      })

      -- ── Python (debugpy) ───────────────────────────────────
      require("dap-python").setup(
        vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
      )
    end,
  },
}
