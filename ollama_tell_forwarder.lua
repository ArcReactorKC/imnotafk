-- Run in MacroQuest with: /lua run ollama_tell_forwarder
local mq = require('mq')
local ImGui = require('ImGui')

local MODEL_NAME = 'llama3'

local function script_dir()
  local info = debug.getinfo(1, 'S')
  local source = info and info.source or ''
  if source:sub(1, 1) == '@' then
    source = source:sub(2)
  end
  return source:match('(.*/)') or './'
end

local config_path = script_dir() .. 'ollama_tell_forwarder_config.lua'

local function load_config()
  local file = io.open(config_path, 'r')
  if not file then
    return {ollama_ip = '127.0.0.1'}
  end

  local contents = file:read('*a')
  file:close()

  local ok, data = pcall(load('return ' .. contents))
  if ok and type(data) == 'table' and type(data.ollama_ip) == 'string' then
    return data
  end

  return {ollama_ip = '127.0.0.1'}
end

local function save_config(config)
  local file = assert(io.open(config_path, 'w'))
  file:write(string.format('{\n  ollama_ip = %q,\n}\n', config.ollama_ip or '127.0.0.1'))
  file:close()
end

local function json_escape(value)
  value = value:gsub('\\', '\\\\')
  value = value:gsub('"', '\\"')
  value = value:gsub('\n', '\\n')
  value = value:gsub('\r', '\\r')
  return value
end

local function json_unescape(value)
  value = value:gsub('\\n', '\n')
  value = value:gsub('\\r', '\r')
  value = value:gsub('\\"', '"')
  value = value:gsub('\\\\', '\\')
  return value
end

local function send_to_ollama(config, teller, message)
  local prompt = string.format('Tell from %s: %s', teller, message)
  local payload = string.format(
    '{"model":"%s","prompt":"%s","stream":false}',
    json_escape(MODEL_NAME),
    json_escape(prompt)
  )
  local url = string.format('http://%s:11434/api/generate', config.ollama_ip)
  local cmd = string.format(
    "curl -s -X POST %q -H 'Content-Type: application/json' -d %q",
    url,
    payload
  )

  local handle = io.popen(cmd)
  if handle then
    local response = handle:read('*a')
    handle:close()
    if response then
      local reply = response:match('\"response\"%s*:%s*\"(.-)\"')
      if reply then
        reply = json_unescape(reply):gsub('%s+$', '')
        if reply ~= '' then
          mq.cmdf('/tell %s %s', teller, reply)
        end
      end
    end
  end
end

local config = load_config()
local should_exit = false
local is_running = false
local is_open = true
local tell_queue = {}

mq.event('TellForwarder', "#1 tells you, '#2'", function(teller, message)
  if is_running then
    table.insert(tell_queue, {teller = teller, message = message})
  end
end)

local function render_gui()
  local draw_window
  is_open, draw_window = ImGui.Begin('Ollama Tell Forwarder', is_open, ImGuiWindowFlags.AlwaysAutoResize)

  if draw_window then
    local changed
    changed, config.ollama_ip = ImGui.InputText('Ollama IP', config.ollama_ip)
    if changed then
      save_config(config)
    end

    if is_running then
      if ImGui.Button('Stop') then
        is_running = false
      end
    else
      if ImGui.Button('Start') then
        is_running = true
      end
    end

    ImGui.SameLine()
    ImGui.Text(is_running and 'Forwarding /tell messages.' or 'Forwarding paused.')
  end

  ImGui.End()

  if not is_open then
    should_exit = true
    is_running = false
  end
end

mq.imgui.init('ollama_tell_forwarder', render_gui)

while not should_exit do
  mq.delay(10)
  mq.doevents()

  if is_running and #tell_queue > 0 then
    local entry = table.remove(tell_queue, 1)
    if entry then
      send_to_ollama(config, entry.teller, entry.message)
    end
  end
end

save_config(config)
