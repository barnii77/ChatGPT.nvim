-- module represents a lua module for the plugin
local M = {}

local Layout = require("nui.layout")
local Popup = require("nui.popup")

local ChatInput = require("chatgpt.input")
local Chat = require("chatgpt.chat")
local Api = require("chatgpt.api")
local Config = require("chatgpt.config")
local Prompts = require("chatgpt.prompts")
local Edits = require("chatgpt.code_edits")
local Settings = require("chatgpt.settings")
-- local InlineEdit = require("chatgpt.flows.inline_edit")

local open_chat = function()
  local chat, chat_input, layout, chat_window

  local scroll_chat = function(direction)
    local speed = vim.api.nvim_win_get_height(chat_window.winid) / 2
    local input = direction > 0 and [[]] or [[]]
    local count = math.abs(speed)

    vim.api.nvim_win_call(chat_window.winid, function()
      vim.cmd([[normal! ]] .. count .. input)
    end)
  end

  chat_window = Popup(Config.options.chat_window)
  chat_input = ChatInput(Config.options.chat_input, {
    prompt = Config.options.chat_input.prompt,
    on_close = function()
      chat:close()
      Api.close()
      layout:unmount()
    end,
    on_submit = vim.schedule_wrap(function(value)
      if chat:isBusy() then
        vim.notify("I'm busy, please wait a moment...", vim.log.levels.WARN)
        return
      end
      -- clear input
      vim.api.nvim_buf_set_lines(chat_input.bufnr, 0, 1, false, { "" })

      chat:addQuestion(value)
      chat:showProgess()

      local params = vim.tbl_extend("keep", { prompt = chat:toString() }, Settings.params)
      Api.completions(params, function(answer)
        chat:addAnswer(answer)
      end)
    end),
  })

  local params = Config.options.openai_params
  local settings_panel = Settings.get_settings_panel("completions", params)
  layout = Layout(
    Config.options.chat_layout,
    Layout.Box({
      Layout.Box(chat_window, { grow = 1 }),
      Layout.Box(chat_input, { size = 3 }),
    }, { dir = "col", grow = 1 })
  )

  --
  -- add keymaps
  --
  -- yank last answer
  chat_input:map("i", Config.options.keymaps.yank_last, function()
    local msg = chat:getSelected()
    vim.fn.setreg(Config.options.yank_register, msg.text)
    vim.notify("Successfully copied to yank register!", vim.log.levels.INFO)
  end, { noremap = true })

  -- scroll down
  chat_input:map("i", Config.options.keymaps.scroll_down, function()
    scroll_chat(1)
  end, { noremap = true, silent = true })

  -- scroll up
  chat_input:map("i", Config.options.keymaps.scroll_up, function()
    scroll_chat(-1)
  end, { noremap = true, silent = true })

  -- close
  local close_keymaps = Config.options.keymaps.close
  if type(close_keymaps) ~= "table" then
    close_keymaps = { close_keymaps }
  end

  for _, keymap in ipairs(close_keymaps) do
    chat_input:map("i", keymap, function()
      chat_input.input_props.on_close()
    end, { noremap = true, silent = true })
  end

  -- toggle settings
  local settings_open = false
  for _, popup in ipairs({ settings_panel, chat_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, "<C-o>", function()
        if settings_open then
          layout:update(Layout.Box({
            Layout.Box(chat_window, { grow = 1 }),
            Layout.Box(chat_input, { size = 3 }),
          }, { dir = "col" }))
          settings_panel:hide()
          vim.api.nvim_set_current_win(chat_input.winid)
        else
          layout:update(Layout.Box({
            Layout.Box({
              Layout.Box(chat_window, { grow = 1 }),
              Layout.Box(chat_input, { size = 3 }),
            }, { dir = "col", grow = 1 }),
            Layout.Box(settings_panel, { size = 40 }),
          }, { dir = "row" }))
          settings_panel:show()
          settings_panel:mount()

          vim.api.nvim_set_current_win(settings_panel.winid)
          vim.api.nvim_buf_set_option(settings_panel.bufnr, "modifiable", false)
          vim.api.nvim_win_set_option(settings_panel.winid, "cursorline", true)
        end
        settings_open = not settings_open
      end, {})
    end
  end

  -- toggle panes
  local active_panel = chat_input
  for _, popup in ipairs({ settings_panel, chat_input }) do
    for _, mode in ipairs({ "n", "i" }) do
      popup:map(mode, "<Tab>", function()
        if active_panel == settings_panel then
          vim.api.nvim_set_current_win(chat_input.winid)
          active_panel = chat_input
        else
          vim.api.nvim_set_current_win(settings_panel.winid)
          vim.api.nvim_buf_set_option(settings_panel.bufnr, "modifiable", false)
          vim.api.nvim_win_set_option(settings_panel.winid, "cursorline", true)
          active_panel = settings_panel
        end
      end, {})
    end
  end

  -- mount chat component
  layout:mount()

  -- initialize chat
  chat = Chat:new(chat_window.bufnr, chat_window.winid)
  chat = Chat:new(chat_window.bufnr, chat_window.winid, display_input_suffix)

  -- set custom filetype
  vim.api.nvim_buf_set_option(chat_window.bufnr, "filetype", Config.options.chat_window.filetype)

  return chat, chat_input, chat_window
end

M.openChat = function()
  local chat, _, _ = open_chat()
  chat:welcome()
end

M.open_chat_with_awesome_prompt = function()
  Prompts.selectAwesomePrompt({
    cb = vim.schedule_wrap(function(act, prompt)
      local chat, _, chat_window = open_chat()
      -- TODO: dry
      chat_window.border:set_text("top", " ChatGPT - Acts as " .. act .. " ", "center")

      chat:addQuestion(prompt)
      chat:showProgess()

      local params = vim.tbl_extend("keep", { prompt = chat:toString() }, Settings.params)
      Api.completions(params, function(answer)
        chat:addAnswer(answer)
      end)
    end),
  })
end

M.edit_with_instructions = Edits.edit_with_instructions
-- M.inline_edit = InlineEdit.run

return M
