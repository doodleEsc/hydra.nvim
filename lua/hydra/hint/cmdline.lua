local class = require('hydra.lib.class')
local Hint = require('hydra.hint.hint')
local util = require('hydra.lib.util')
local strdisplaywidth = vim.fn.strdisplaywidth
local nvim_echo = vim.api.nvim_echo
local vim_options = require('hydra.hint.vim-options')
local M = {}

--------------------------------------------------------------------------------

---@class hydra.hint.AutoCmdline : hydra.Hint
---@field message hydra.EchoChunk[]
local HintAutoCmdline = class(Hint)

---@param hydra Hydra
function HintAutoCmdline:initialize(hydra)
   Hint.initialize(self, hydra)
   self.o = hydra.options.o
   self.height = 1
end

function HintAutoCmdline:_make_message()
   ---Available screen width for echo message
   ---@type integer
   local space = vim.v.echospace - 1

   local hint = { {' '} } ---@type  hydra.EchoChunk[]

   local continue = true

   if self.config.show_name then
      hint[#hint+1] = { (self.hydra_name or 'HYDRA')..': ' }
      space = space - strdisplaywidth(hint[#hint][1])
   end

   local heads = self:_swap_head_with_index()
   for _, head_spec in ipairs(heads) do
      local desc = head_spec.desc
      if desc ~= false then
         continue, space = self:_add_chunk(hint, space, { head_spec.head, 'Hydra'..head_spec.color })
         if not continue then break end

         if desc then
            desc = string.format(': %s, ', desc)
         else
            desc = ', '
         end
         continue, space = self:_add_chunk(hint, space, { desc })
         if not continue then break end
      end
   end
   hint[#hint][1] = hint[#hint][1]:gsub(', $', '')

   self.message = hint
end

---@param msg hydra.EchoChunk[]
---@param space integer
---@param chunk hydra.EchoChunk
---@return boolean continue Can we continue after adding this chunk?
---@return number space Available space in echo area after adding this chunk.
function HintAutoCmdline:_add_chunk(msg, space, chunk)
   local new_space = space - strdisplaywidth(chunk[1])
   if new_space > 0 then
      msg[#msg+1] = chunk
      return true, new_space
   else
      local text, hl = chunk[1], chunk[2]
      text = util.split_string(text) ---@diagnostic disable-line
      local new_text = {} ---@type string[]
      local len
      for _, word in ipairs(text) do
         len = strdisplaywidth(word)
         if len < space then
            table.insert(new_text, word)
            space = space - len
         elseif space > 3 then
            table.insert(new_text, '...')
            space = space - 3
            break
         else
            break
         end
      end
      new_text = table.concat(new_text) ---@diagnostic disable-line
      msg[#msg+1] = { new_text, hl }
      return false, space
   end
end

function HintAutoCmdline:show()
   -- 'shortmess' 'shm'	string	(Vim default "filnxtToOF", Vi default: "S")
   if not self.message then self:_make_message() end
   if self.o.cmdheight < self.height then
      self.o.cmdheight = self.height
   end
   vim.cmd 'redraw'
   nvim_echo(self.message, false, {})
end

HintAutoCmdline.update = HintAutoCmdline.show

function HintAutoCmdline:leave()
   local line ---@type hydra.EchoChunk[]
   if self.hydra_color == 'amaranth' then
      -- 'An Amaranth Hydra can only exit through a blue head'
      line = {
         {'\n'}, {' An '},
         {'Amaranth', 'HydraAmaranth'},
         {' Hydra can only exit through a blue head'}
      }
   elseif self.hydra_color == 'teal' then
      -- 'A Teal Hydra can only exit through one of its heads'
      line = {
         {'\n'}, {' A '},
         {'Teal', 'HydraTeal'},
         {' Hydra can only exit through one of its heads'}
      }
   end

   ---@type hydra.EchoChunk[]
   local message = vim.deepcopy(self.message)
   vim.list_extend(message, line)

   self.o.cmdheight = self.height + 1
   vim.cmd 'redraw'
   nvim_echo(message, false, {})
end

--------------------------------------------------------------------------------

---@class hydra.hint.ManualCmdline : hydra.hint.AutoCmdline
---@field hint string[]
---@field height integer
---@field message hydra.EchoChunk[]
---@field need_to_update boolean
local HintManualCmdline = class(HintAutoCmdline)

---@param hydra Hydra
---@param hint string
function HintManualCmdline:initialize(hydra, hint)
   HintAutoCmdline.initialize(self, hydra)
   self.need_to_update = false

   self.config.funcs = setmetatable(self.config.funcs or {}, {
      __index = vim_options
   })

   self.hint = vim.split(hint, '\n')
   -- Remove last empty string.
   if self.hint and self.hint[#self.hint] == '' then
      self.hint[#self.hint] = nil
   end
end

function HintManualCmdline:_make_message()
   ---@type string[]
   local hint = vim.deepcopy(self.hint)

   ---@type table<string, hydra.HeadSpec>
   local heads = vim.deepcopy(self.heads)

   self.message = {}

   local space, continue
   local chunks ---@type hydra.EchoChunk[]
   for _, line in ipairs(hint) do
      ---Available screen width for echo message
      ---@type number
      space = vim.v.echospace
      chunks = {}

      line = line:gsub('%^', '')

      local start, stop, found = 0, 0, nil
      while start do
         start, stop, found = line:find('%%{(.-)}', 1)
         ---@cast found string
         if start then
            self.need_to_update = true

            local fun = self.config.funcs[found]
            if not fun then
               error(string.format('[Hydra] "%s" not present in "config.hint.functions" table', found))
            end

            line = table.concat({
               line:sub(1, start - 1),
               fun(),
               line:sub(stop + 1)
            })
         end
      end

      start, stop, found = 0, 0, nil
      while start do
         start, stop, found = line:find('_(.-)_', stop + 1)
         ---@cast found string
         if found and vim.startswith(found, [[\]]) then found = found:sub(2) end
         if start then
            if not heads[found] then
               error(string.format('[Hydra] docsting error, head "%s" does not exist', found))
            end
            local color = heads[found].color

            table.insert(chunks, { line:sub(1, start-1) })
            table.insert(chunks, { found, 'Hydra'..color })

            line = line:sub(stop+1)
            heads[found] = nil
            start, stop = 0, 0
         end
      end
      table.insert(chunks, { line })

      for _, chunk in ipairs(chunks) do
         continue, space = self:_add_chunk(self.message, space, chunk)
         if not continue then
            break
         end
      end

      table.insert(self.message, {'\n'})
   end

   -- Remove heads with `desc = false`.
   for head, properties in pairs(heads) do
      if properties.desc == false then
         heads[head] = nil
      end
   end

   if vim.tbl_isempty(heads) then
      table.remove(self.message) -- remove last '\n' symbol
      self.height = #hint
   else -- There are remain hydra heads, that not present in manually created hint.
      table.insert(self.message, {' '})

      local heads_lhs = vim.tbl_keys(heads) ---@type string[]
      table.sort(heads_lhs, function (a, b)
         return heads[a].index < heads[b].index
      end)

      local line = {}
      for _, head in pairs(heads_lhs) do
         local head_spec = self.heads[head]
         continue, space = self:_add_chunk(line, space, { head_spec.head, 'Hydra'..head_spec.color })
         if not continue then break end

         local desc = head_spec.desc
         if desc then
            desc = string.format(': %s, ', desc)
         else
            desc = ', '
         end
         continue, space = self:_add_chunk(line, space, { desc })
         if not continue then break end
      end
      line[#line][1] = line[#line][1]:gsub(', $', '')
      vim.list_extend(self.message, line)
      self.height = #hint + 1
   end

   -- self:debug(self.message)
end

--------------------------------------------------------------------------------

M.HintAutoCmdline = HintAutoCmdline
M.HintManualCmdline = HintManualCmdline
return M
