-- Copy from: https://github.com/simrat39/rust-tools.nvim/blob/06c9361a0e750a44f8f489c071bf3424ae733d5e/lua/rust-tools/lsp.lua
-- MIT License, Copyright (c) 2022 Simrat

local rt = require('rust-tools')
local lspconfig_utils = require('lspconfig.util')

local M = {}

local function setup_commands()
    local lsp_opts = rt.config.options.server

    lsp_opts.commands = vim.tbl_deep_extend('force', lsp_opts.commands or {}, {
        RustCodeAction = {
            rt.code_action_group.code_action_group,
        },
        RustViewCrateGraph = {
            function(backend, output, pipe)
                rt.crate_graph.view_crate_graph(backend, output, pipe)
            end,
            '-nargs=* -complete=customlist,v:lua.rust_tools_get_graphviz_backends',
            description = '`:RustViewCrateGraph [<backend> [<output>]]` Show the crate graph',
        },
        RustDebuggables = {
            rt.debuggables.debuggables,
        },
        RustExpandMacro = { rt.expand_macro.expand_macro },
        RustOpenExternalDocs = {
            rt.external_docs.open_external_docs,
        },
        RustHoverActions = { rt.hover_actions.hover_actions },
        RustHoverRange = { rt.hover_range.hover_range },
        RustEnableInlayHints = {
            rt.inlay_hints.enable,
        },
        RustDisableInlayHints = {
            rt.inlay_hints.disable,
        },
        RustSetInlayHints = {
            rt.inlay_hints.set,
        },
        RustUnsetInlayHints = {
            rt.inlay_hints.unset,
        },
        RustJoinLines = { rt.join_lines.join_lines },
        RustMoveItemDown = {
            rt.move_item.move_item,
        },
        RustMoveItemUp = {
            function()
                require('rust-tools.move_item').move_item(true)
            end,
        },
        RustOpenCargo = { rt.open_cargo_toml.open_cargo_toml },
        RustParentModule = { rt.parent_module.parent_module },
        RustRunnables = {
            rt.runnables.runnables,
        },
        RustSSR = {
            function(query)
                require('rust-tools.ssr').ssr(query)
            end,
            '-nargs=?',
            description = '`:RustSSR [query]` Structural Search Replace',
        },
        RustReloadWorkspace = {
            rt.workspace_refresh.reload_workspace,
        },
    })
end

local function setup_handlers()
    local lsp_opts = rt.config.options.server
    local tool_opts = rt.config.options.tools
    local custom_handlers = {}

    if tool_opts.hover_with_actions then
        vim.notify(
            'rust-tools: hover_with_actions is deprecated, please setup a keybind to :RustHoverActions in on_attach instead'
            ,
            vim.log.levels.INFO
        )
    end

    custom_handlers['experimental/serverStatus'] = rt.utils.mk_handler(
        rt.server_status.handler
    )

    lsp_opts.handlers = vim.tbl_deep_extend(
        'force',
        custom_handlers,
        lsp_opts.handlers or {}
    )
end

local function setup_on_init()
    local lsp_opts = rt.config.options.server
    local old_on_init = lsp_opts.on_init

    lsp_opts.on_init = function(...)
        rt.utils.override_apply_text_edits()
        if old_on_init ~= nil then
            old_on_init(...)
        end
    end
end

local function setup_capabilities()
    local lsp_opts = rt.config.options.server
    local capabilities = vim.lsp.protocol.make_client_capabilities()

    -- snippets
    capabilities.textDocument.completion.completionItem.snippetSupport = true

    -- send actions with hover request
    capabilities.experimental = {
        hoverActions = true,
        hoverRange = true,
        serverStatusNotification = true,
        snippetTextEdit = true,
        codeActionGroup = true,
        ssr = true,
    }

    -- enable auto-import
    capabilities.textDocument.completion.completionItem.resolveSupport = {
        properties = { 'documentation', 'detail', 'additionalTextEdits' },
    }

    -- rust analyzer goodies
    capabilities.experimental.commands = {
        commands = {
            'rust-analyzer.runSingle',
            'rust-analyzer.debugSingle',
            'rust-analyzer.showReferences',
            'rust-analyzer.gotoLocation',
            'editor.action.triggerParameterHints',
        },
    }

    lsp_opts.capabilities = vim.tbl_deep_extend(
        'force',
        capabilities,
        lsp_opts.capabilities or {}
    )
end

local function get_root_dir(filename)
    local fname = filename or vim.api.nvim_buf_get_name(0)
    local cargo_crate_dir = lspconfig_utils.root_pattern('Cargo.toml')(fname)
    local cmd = { 'cargo', 'metadata', '--no-deps', '--format-version', '1' }
    if cargo_crate_dir ~= nil then
        cmd[#cmd + 1] = '--manifest-path'
        cmd[#cmd + 1] = lspconfig_utils.path.join(cargo_crate_dir, 'Cargo.toml')
    end
    local cargo_metadata = ''
    local cm = vim.fn.jobstart(cmd, {
        on_stdout = function(_, d, _)
            cargo_metadata = table.concat(d, '\n')
        end,
        stdout_buffered = true,
    })
    if cm > 0 then
        cm = vim.fn.jobwait({ cm })[1]
    else
        cm = -1
    end
    local cargo_workspace_dir = nil
    if cm == 0 then
        cargo_workspace_dir = vim.fn.json_decode(cargo_metadata)['workspace_root']
    end
    return cargo_workspace_dir
        or cargo_crate_dir
        or lspconfig_utils.root_pattern('rust-project.json')(fname)
        or lspconfig_utils.find_git_ancestor(fname)
end

local function setup_root_dir()
    local lsp_opts = rt.config.options.server
    if not lsp_opts.root_dir then
        lsp_opts.root_dir = get_root_dir
    end
end

function M.setup(opts)
    rt.code_action_group = require('rust-tools.code_action_group')
    rt.commands = require('rust-tools.commands')
    rt.config = require('rust-tools.config')
    rt.crate_graph = require('rust-tools.crate_graph')
    rt.dap = require('rust-tools.dap')
    rt.debuggables = require('rust-tools.debuggables')
    rt.expand_macro = require('rust-tools.expand_macro')
    rt.external_docs = require('rust-tools.external_docs')
    rt.hover_actions = require('rust-tools.hover_actions')
    rt.hover_range = require('rust-tools.hover_range')

    local inlay = require('rust-tools.inlay_hints')
    local hints = inlay.new()
    rt.inlay_hints = {
        enable = function()
            inlay.enable(hints)
        end,
        disable = function()
            inlay.disable(hints)
        end,
        set = function()
            inlay.set(hints)
        end,
        unset = function()
            inlay.unset()
        end,
        cache = function()
            inlay.cache_render(hints)
        end,
        render = function()
            inlay.render(hints)
        end,
    }

    rt.join_lines = require('rust-tools.join_lines')
    rt.lsp = require('rust-tools.lsp')
    rt.move_item = require('rust-tools.move_item')
    rt.open_cargo_toml = require('rust-tools.open_cargo_toml')
    rt.parent_module = require('rust-tools.parent_module')
    rt.runnables = require('rust-tools.runnables')
    rt.server_status = require('rust-tools.server_status')
    rt.ssr = require('rust-tools.ssr')
    rt.standalone = require('rust-tools.standalone')
    rt.workspace_refresh = require('rust-tools.workspace_refresh')
    rt.utils = require('rust-tools.utils.utils')

    rt.config.setup(opts)

    setup_capabilities()
    -- setup on_init
    setup_on_init()
    -- setup root_dir
    setup_root_dir()
    -- setup handlers
    setup_handlers()
    -- setup user commands
    setup_commands()

    rt.commands.setup_lsp_commands()

    if pcall(require, 'dap') then
        rt.dap.setup_adapter()
    end
    return rt.config.options.server
end

return M
