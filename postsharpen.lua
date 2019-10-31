--[[
  This file is part of darktable,
  copyright (c) 2019 Bill Ferguson <wpferguson@gmail.com>
  
  darktable is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.
  
  darktable is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
  
  You should have received a copy of the GNU General Public License
  along with darktable.  If not, see <http://www.gnu.org/licenses/>.
]]
--[[
    postsharpen.lua - sharpen images after they are exported

  TODO
    Finish path substitution so that it mirrors darktables
    Presets - done
]]

-- TODO: Add filename conflict resolution [overwrite|unique] done
--       Add versioning to preferences so that we dont crash on reload
--       Add engine delimiters to preferences

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"
local dtsys = require "lib/dtutils.system"

-- chedk to make sure we can run
du.check_min_api_version("5.0.0")

-- namespace variable
local postsharpen = {
  presets = {},
  substitutes = {},
  placeholders = {"ROLL_NAME","FILE_FOLDER","FILE_NAME","FILE_EXTENSION","ID","VERSION","SEQUENCE","YEAR","MONTH","DAY",
                  "HOUR","MINUTE","SECOND","EXIF_YEAR","EXIF_MONTH","EXIF_DAY","EXIF_HOUR","EXIF_MINUTE","EXIF_SECOND",
                  "STARS","LABELS","MAKER","MODEL","TITLE","CREATOR","PUBLISHER","RIGHTS","USERNAME","PICTURES_FOLDER",
                  "HOME","DESKTOP"},
  widgets = {},
}

-- - - - - - - - - - - - - - - - - - - - - - - -
-- C O N S T A N T S
-- - - - - - - - - - - - - - - - - - - - - - - -

local MODULE_NAME = "postsharpen"
local PS = dt.configuration.running_os == "windows" and  "\\"  or  "/"
local USER = os.getenv("USERNAME")
local HOME = os.getenv("HOME")
local PICTURES = HOME .. PS .. dt.configuration.running_os == "windows" and "My Pictures" or "Pictures"
local DESKTOP = HOME .. PS .. "Desktop"

-- - - - - - - - - - - - - - - - - - - - - - - -
-- T R A N S L A T I O N S
-- - - - - - - - - - - - - - - - - - - - - - - -
local gettext = dt.gettext
gettext.bindtextdomain(MODULE_NAME, dt.configuration.config_dir..PS.."lua"..PS.."locale"..PS)

local function _(msgid)
  return gettext.dgettext(MODULE_NAME, msgid)
end


-- - - - - - - - - - - - - - - - - - - - - - - -
-- F U N C T I O N S
-- - - - - - - - - - - - - - - - - - - - - - - -

local function create_slider(label, tooltip, smin, smax, hmin, hmax, step, digits, name, datatype, value)
  postsharpen.widgets[name] = dt.new_widget("slider"){
    label = label,
    tooltip = tooltip,
    soft_min = smin,
    soft_max = smax,
    hard_min = hmin,
    hard_max = hmax,
    step = step,
    digits = digits,
    value = value,
  }
  dt.print_log("value is " .. postsharpen.widgets[name].value)
  dt.print_log("returning name " .. name)
  return name
end

local function create_combobox(label, tooltip, choices, name, datatype, value)
  postsharpen.widgets[name] = dt.new_widget("combobox"){
    label = label,
    tooltip = tooltip,
    selected = value,
    table.unpack(choices)
  }
  dt.print_log("combobox selected is " .. postsharpen.widgets[name].selected)
  return name
end

local function create_check_button(label, tooltip, name, datatype, value)
  postsharpen.widgets[name] = dt.new_widget("check_button"){
    label = label,
    tooltip = tooltip,
    value = value,
  }
  return name
end

local function sub1(num)
  dt.print_log("in sub1...")
  num = tonumber(num)
  return num - 1
end

local function div100(num)
  dt.print_log("in div100")
  num = tonumber(num)
  return num / 100.
end

local function update_combobox_choices(combobox, choice_table, selected)
  local items = #combobox
  local choices = #choice_table
  for i, name in ipairs(choice_table) do 
    combobox[i] = name
  end
  if choices < items then
    for j = items, choices + 1, -1 do
      combobox[j] = nil
    end
  end
  combobox.value = selected
end

local function read_presets()
  -- read the presets from preferences
  local presets = du.split(dt.preferences.read(MODULE_NAME, "preset_list", "string"), ',')
  dt.print_log(#presets .. " read")
  if(#presets == 0) then
    presets = {}
  end
  return presets
end

local function save_preferences(name)
  -- save current widget settings
  local pref_name = "preferences"
  if name then
    pref_name = name
  end
  local prefs = {}
  prefs[1] = postsharpen.widgets["output_path"].text
  prefs[2] = postsharpen.widgets["overwrite"].selected
  prefs[3] = postsharpen.widgets["method_chooser"].selected
  local i = 3
  --[[
    iterating over a table using pairs doesn't guarentee the order the
    items will be returned in, so we have to force the order so that we
    can apply it correctly when we read it back.
  ]]
  -- determine how many engines we have
  local num_engines = 0
  for engine, vals in pairs(postsharpen.engines) do
    num_engines = num_engines + 1
  end
  dt.print_log("found " .. num_engines .. " engines")
  for j = 1, num_engines do 
    for engine, vals in pairs(postsharpen.engines) do
      if vals.stack_pos == j then
        for name, v in pairs(vals.widgets) do
          local widget_name = engine .. "_" .. name
          dt.print_log("processing " .. widget_name)
          local value = nil
          if v.wtype == "combobox" then
            value = postsharpen.widgets[widget_name].selected
          elseif v.wtype == "check_button" then
            value = postsharpen.widgets[widget_name].value
            if value == true then
              value = 1
            else
              value = 0
            end
          else
            value = postsharpen.widgets[widget_name].value
          end
          prefs[i + v.widget_pos] = value
        end
        i = i + vals.num_widgets
      end
    end
  end
  dt.preferences.write(MODULE_NAME, pref_name, "string", table.concat(prefs, ','))
  if dt.preferences.read(MODULE_NAME, "initialized", "bool") == false then
    dt.preferences.write(MODULE_NAME, "initialized", "bool", true)
  end
end

local function apply_saved_preferences(name)
  -- load saved preferences and apply them
  if dt.preferences.read(MODULE_NAME, "initialized", "bool") then
    dt.print_log("preferences are initialized")
    local pref_name = "preferences"
    if name then
      pref_name = name
    end
    dt.print_log("pref name is " .. pref_name)
    local pref_string = dt.preferences.read(MODULE_NAME, pref_name, "string")
    dt.print_log(pref_string)
    local prefs = du.split(dt.preferences.read(MODULE_NAME, pref_name, "string"), ',')
    dt.print_log("number of preferences is " .. #prefs)
    postsharpen.widgets["output_path"].text = prefs[1]
    dt.print_log("set output path")
    postsharpen.widgets["overwrite"].selected = prefs[2]
    dt.print_log("set overwrite")
    postsharpen.widgets["method_chooser"].selected = prefs[3]
    dt.print_log("set method_chooser")
    local i = 3
  -- determine how many engines we have
    local num_engines = 0
    for engine, vals in pairs(postsharpen.engines) do
      num_engines = num_engines + 1
    end
    dt.print_log("found " .. num_engines .. " engines")
    for j = 1, num_engines do 
      for engine, vals in pairs(postsharpen.engines) do
        if vals.stack_pos == j then
          for name, v in pairs(vals.widgets) do
            local widget_name = engine .. "_" .. name
            dt.print_log("processing " .. widget_name)
            if v.wtype == "combobox" then
              postsharpen.widgets[widget_name].selected = prefs[i + v.widget_pos]
            elseif v.wtype == "check_button" then
              local value = prefs[i + v.widget_pos]
              if value == 1 then
                value = true
              else
                value = false
              end
              postsharpen.widgets[widget_name].value = value
            else
              postsharpen.widgets[widget_name].value = prefs[i + v.widget_pos]
            end
          end
          i = i + vals.num_widgets
          -- in case we add new engines, they won't have presets on the first run
          if i == #prefs then
            return
          end
        end
      end
    end
  else
    dt.print_log("postsharpen not initialized, loading some presets")
    -- load a couple of presets to help
    dt.preferences.write(MODULE_NAME, "preset_list", "string", "print,web")
    dt.print_log("wrote preset list")
    dt.preferences.write(MODULE_NAME, "web", "string", "$(FILE_FOLDER)/darktable_exported/$(FILE_NAME),1,2,1.0,0.79999995231628,1.0,0.79999995231628,100.0,10.0,1.0,2.0,1,0")
    dt.print_log("wrote preset web")
    dt.preferences.write(MODULE_NAME, "print", "string", "$(FILE_FOLDER)/darktable_exported/$(FILE_NAME),1,2,1.0,0.79999995231628,2.0,1.7999999523163,100.0,25.0,1.0,2.0,1,0")
    dt.print_log("wrote preset print")
    local presets = read_presets()
    dt.print_log("read " .. #presets .. " presets")
    table.insert(presets, 1, "none")
    dt.print_log("added none to presets")
    update_combobox_choices(postsharpen.widgets["preset_list"], presets, 1)
    dt.print_log("updated combobox")
    save_preferences()
  end
end

local function save_presets()
  -- save the presets to preferences
  local presets = {}
  local combobox = postsharpen.widgets["preset_list"]
  for i = 1, #combobox do
    if combobox[i] ~= "none" then
      table.insert(presets, #presets + 1, combobox[i])
    end
  end
  table.sort(presets)
  dt.preferences.write(MODULE_NAME, "preset_list", "string", table.concat(presets, ','))
end

local function create_preset()
  -- create a preset
  if postsharpen.widgets["preset_new_name"].text ~= "" and postsharpen.widgets["preset_new_name"].text ~= "none" then
    save_preferences(postsharpen.widgets["preset_new_name"].text)
    local presets = read_presets()
    dt.print_log("read presets returned " .. #presets .. " presets")
    if #presets == 0 then
      dt.print_log("adding new preset to empty table")
      presets[1] = postsharpen.widgets["preset_new_name"].text
    end
    dt.print_log("now have " .. #presets .. " presets")
    presets[#presets + 1] = postsharpen.widgets["preset_new_name"].text
    table.sort(presets)
    table.insert(presets, 1, "none")
    choice = nil
    for i, name in ipairs(presets) do
      if name == postsharpen.widgets["preset_new_name"].text then
        choice = i
      end
    end
    update_combobox_choices(postsharpen.widgets["preset_list"], presets, choice)
    save_presets()
    postsharpen.widgets["preset_new_name"].text = ""
  end
end

local function update_preset()
  -- update an existing preset
  if postsharpen.widgets["preset_list"].value ~= "none" then
    save_preferences(postsharpen.widgets["preset_list"].value)
  end
end

local function delete_preset()
  -- delete a preset
  local choice
  if postsharpen.widgets["preset_list"].value ~= "none" then
    local presets = read_presets()
    choice = nil
    for i, name in ipairs(presets) do
      if name == postsharpen.widgets["preset_list"].value then
        choice = i
      end
    end

    local tmp = table.remove(presets, choice)
    dt.print_log(tmp .. " removed from presets")

    table.insert(presets, 1, "none")
    update_combobox_choices(postsharpen.widgets["preset_list"], presets, 1)
    save_presets()
  end
end

local function apply_preset()
  -- configure the settings from a preset
  if postsharpen.widgets["preset_list"] then -- to get around initialization issue
    if postsharpen.widgets["preset_list"].selected > 1 then
      apply_saved_preferences(postsharpen.widgets["preset_list"].value)
    end
  end
end

local function stop_job(job)
  job.valid = false
end

local function build_substition_list(image, sequence, exp_img, datetime, username, pic_folder, home, desktop)
 -- build the argument substitution list from each image
 -- local datetime = os.date("*t")
 local colorlabels = {}
 if image.red then table.insert(colorlabels, "red") end
 if image.yellow then table.insert(colorlabels, "yellow") end
 if image.green then table.insert(colorlabels, "green") end
 if image.blue then table.insert(colorlabels, "blue") end
 if image.purple then table.insert(colorlabels, "purple") end
 local labels = #colorlabels == 1 and colorlabels[1] or du.join(colorlabels, ",")
 local eyear,emon,eday,ehour,emin,esec = string.match(image.exif_datetime_taken, "(%d-):(%d-):(%d-) (%d-):(%d-):(%d-)$")
 local replacements = {image.film,image.path,df.get_filename(exp_img),df.get_filetype(exp_img),image.id,image.duplicate_index,
                       sequence,datetime.year,string.format("%02d", datetime.month),string.format("%02d", datetime.day),string.format("%02d", datetime.hour),
                       string.format("%02d", datetime.min),string.format("%02d", datetime.sec),eyear,emon,eday,ehour,emin,esec,image.rating,labels,
                       image.exif_maker,image.exif_model,image.title,image.creator,image.publisher,image.rights,username,pic_folder,home,desktop}

  for i=1,#postsharpen.placeholders,1 do postsharpen.substitutes[postsharpen.placeholders[i]] = replacements[i] end
end

local function substitue_list(str)
  -- replace the substitution variables in a string
  for match in string.gmatch(str, "%$%(.-%)") do
    local var = string.match(match, "%$%((.-)%)")
    str = string.gsub(str, "%$%("..var.."%)", postsharpen.substitutes[var])
  end
  return str
end

local function clear_substitute_list()
  for i=1,#postsharpen.placehoders,1 do postsharpen.substitutes[postsharpen.placeholders[i]] = nil end
end

local function show_status(storage, image, format, filename, number, total, high_quality, extra_data)
  dt.print(_("exporting ")..tostring(number).." / "..tostring(total))   
  dt.print_log("exporting " .. image.filename .. " to " .. filename)
  if format.quality then
    extra_data["quality"] = format.quality
  end
end

local function setup(storage, img_format, image_table, high_quality, extra_data)
  -- set up for the export
  -- save widget values in the extra_data table
  extra_data["images"] = image_table
  extra_data["output_path"] = postsharpen.widgets["output_path"].text
  extra_data["method"] = postsharpen.widgets["method_chooser"].value
  extra_data["filetype"] = img_format.extension
  dt.print_log("image format is " .. img_format.extension)
  save_preferences()
end

local function sharpen(storage, image_table, extra_data)
  -- sharpen the exported images
  local images = extra_data["images"]
  local engine = string.gsub(postsharpen.widgets["method_chooser"].value, ' ', '_')
  local format = postsharpen.engines[engine]["format"]
  local bin = postsharpen.engines[engine]["bin"]
  local switch = postsharpen.engines[engine]["switch"]
  local prog_args = {}

  for k,v in pairs(postsharpen.engines[engine]["widgets"]) do
    local widget_name = engine .. "_" .. k
    local widget_type = v.wtype
    local val = nil
    if widget_type == "combobox" then
      val = postsharpen.widgets[widget_name].selected
    elseif widget_type == "check_button" then
      val = 0
      if postsharpen.widgets[widget_name].value == true then
        val = 1
      end
    else
      val = postsharpen.widgets[widget_name].value
    end
    if v.adjustment then
      dt.print_log("took the adjustment")
      val = v.adjustment(val)
    end
    prog_args[v.widget_pos] = val
  end

  local sharpen_opts = string.format(format, table.unpack(prog_args))
  dt.print_log("sharpen_opts are " .. sharpen_opts)

  local prog = df.check_if_bin_exists(bin)

  local datetime = os.date("*t")
  local destination = nil
  local job = dt.gui.create_job(_("sharpen images"), true, stop_job)
  for i,image in ipairs(images) do
    dt.print_log("exported image filename is " .. image_table[image])
    build_substition_list(image, i, image_table[image], datetime, USER, HOME, PICTURES, DESKTOP)
    local destination = substitue_list(extra_data["output_path"])
    local path = df.get_path(destination)
    if not df.check_if_file_exists(path) then
      df.mkdir(path)
    end
    if postsharpen.widgets["overwrite"].value == "create unique filename" then
      destination = df.create_unique_filename(destination)
    end
    local filename = image_table[image]
    local cmd = nil
    if bin == "gmic" then
      cmd = prog .. " " .. filename .. switch .. sharpen_opts .. "-o " .. destination
      if extra_data["quality"] then
        cmd = cmd .. "," .. extra_data["quality"]
      end
    else
      cmd = prog .. switch .. sharpen_opts .. filename .. " " .. destination
    end
    dt.print_log("running " .. cmd)
    dtsys.external_command(cmd)
    os.remove(filename)
    job.percent = i / #images
  end
  stop_job(job)
--  local result = dtsys.external_command(sharpen_cmd .. df.get_path(destination) .. PS .. "*." .. extra_data["filetype"])
end

-- - - - - - - - - - - - - - - - - - - - - - - -
-- M A I N
-- - - - - - - - - - - - - - - - - - - - - - - -

postsharpen['engines'] = {
  sharpen = {
    name = 'sharpen',
    stack_pos = 1,
    bin = 'convert',
    switch = ' -sharpen',
    format = ' %dx%.02f ',
    num_widgets = 2,
    widgets = {
      radius  = {widget_pos = 1, wtype = 'slider', values = {_("radius"), _("the extent of the effect, leave at 0 to let the program choose the best value"), 
                                                  0, 5, 0, 5, 1, 0, "sharpen_radius", "integer", 1}, adjustment = nil},
      sigma   = {widget_pos = 2, wtype = 'slider', values = {_("sigma"), _("the amount of sharpening"), 
                                                 0, 5, 0, 5, 0.1, 1, "sharpen_sigma", "float", .75}, adjustment = nil}
    }
  },
  unsharp_mask = {
    name = 'unsharp mask',
    stack_pos = 2,
    bin = 'convert',
    switch = ' -unsharp',
    format = ' %.02fx%.02f+%.02f+%.02f ',
    num_widgets = 4,
    widgets = {
      radius    = {widget_pos = 1, wtype = 'slider', values = {_("radius"), _("the radius of the Gaussian, in pixels, not counting the center pixel"),
                                                  0, 5, 0, 5, 0.1, 1, "unsharp_mask_radius", "float", 1.0}, adjustment = nil},
      sigma     = {widget_pos = 2, wtype = 'slider', values = {_("sigma"), _("the standard deviation of the Gaussian, in pixels.  Should be >= radius"), 
                                                   0, 5, 0, 5, 0.1, 1, "unsharp_mask_sigma", "float", 0.8}, adjustment = nil},
      amount    = {widget_pos = 3, wtype = 'slider', values = {_("amount"), _("the percentage of the difference between the original and the blur image that is added back into the original"), 
                                                  0, 500, 0, 500, 1, 0, "unsharp_mask_amount", "integer", 100}, adjustment = div100},
      threshold = {widget_pos = 4, wtype = 'slider', values = {_("threshold"), _("the threshold to limit the effect.  0 is full effect and 100 is no effect"),
                                                     0, 100, 0, 100, 1, 0, "unsharp_mask_threshold", "integer", 10}, adjustment = div100}
    }
  },
  richardson_lucy_deconvolve = {
    name = "richardson lucy deconvolve",
    stack_pos = 3,
    bin = 'gmic',
    switch = " -fx_unsharp_richardsonlucy ",
    format = ' %.02f,%d,%d,%d ',
    num_widgets = 4,
    widgets = {
      sigma      = {widget_pos = 1, wtype = 'slider',       values = {_("sigma"), _(""), 0.5,10,0.5,10,0.1,1, "richardson_lucy_deconvolve_sigma", "float", 1.0}, adjustment = nil},
      iterations = {widget_pos = 2, wtype = 'slider',       values = {_("iterations"), _(""), 1,100,1,100,1,0, "richardson_lucy_deconvolve_iterations", "integer", 10}, adjustment = nil},
      blur       = {widget_pos = 3, wtype = 'combobox',     values = {_("blur"), _(""), {"exponential", "gaussian"}, "richardson_lucy_deconvolve_blur", "integer", 2}, adjustment = sub1},
      cut        = {widget_pos = 4, wtype = 'check_button', values = {_("cut"), _(""), "richardson_lucy_deconvolve_cut", "bool", true}, adjustment = nil}
    }
  }
}

local method_stack_items = {}
local method_stack_choices = {}

for method, v1 in pairs(postsharpen.engines) do 
  dt.print_log("processing value " .. method)
  dt.print_log("creating new widget table")
  local widget_table = {}
  dt.print_log("num_widgets is " .. v1.num_widgets)
  for i = 1, v1.num_widgets do 
    widget_table[i] = ""
  end
  dt.print_log("length of widget table is " .. #widget_table)
  for key,val in pairs(v1.widgets) do
    dt.print_log("processing widget " .. key)
    dt.print_log("widget type is " .. postsharpen.engines[method]["widgets"][key]['wtype'])
    dt.print_log("position is " .. val.widget_pos)
    if val.wtype == "slider" then
      widget_table[val.widget_pos] = postsharpen.widgets[create_slider(table.unpack(val.values))]
    elseif val.wtype == "combobox" then 
      widget_table[val.widget_pos] = postsharpen.widgets[create_combobox(table.unpack(val.values))]
    elseif val.wtype == "check_button" then
      widget_table[val.widget_pos] = postsharpen.widgets[create_check_button(table.unpack(val.values))]
    else
      dt.print_error("unknown widget type")
    end
    dt.print_log("length of widget table is now " .. #widget_table)
  end
  dt.print_log("widgets created, putting them in a box")
  dt.print_log("widget 2 is " .. widget_table[2].label)
  dt.print_log("number of widgets in table is " .. #widget_table)
  dt.print_log("label name is " .. v1.name)
  postsharpen.widgets[v1.name] = dt.new_widget("box"){
    orientation = "vertical",
    dt.new_widget("label"){label = v1.name},
    table.unpack(widget_table),
  }
  method_stack_items[v1.stack_pos] = postsharpen.widgets[v1.name]
  method_stack_choices[v1.stack_pos] = v1.name
end


local tmp = "$(FILE_FOLDER)/darktable_exported/$(FILE_NAME)"
postsharpen.widgets["output_path"] = dt.new_widget("entry"){
  text = tmp,
  editable = true,
}

dt.print_log("dreated output_path")

postsharpen.widgets["overwrite"] = dt.new_widget("combobox"){
  label = "on conflict",
  value = 1,
  "create unique filename", "overwrite",
}

dt.print_log("created overwrite")

postsharpen.widgets["method_stack"] = dt.new_widget("stack"){
  table.unpack(method_stack_items),
 }

 dt.print_log("created method_stack")

tmp = 1 
postsharpen.widgets["method_chooser"] = dt.new_widget("combobox"){
  label = _("method"),
  tooltip = _("select sharpening method"),
  changed_callback = function(self)
    postsharpen.widgets["method_stack"].active = self.selected
  end,
  value = tmp,
  table.unpack(method_stack_choices),
}

dt.print_log("created method_chooser")

local saved_presets = read_presets()
table.insert(saved_presets, 1, "none")
-- preset widgets
postsharpen.widgets["preset_list"] = dt.new_widget("combobox"){
  tooltip = "select the preset to apply",
  changed_callback = function(self)
    apply_preset()
  end,
  value = 1,
  table.unpack(saved_presets)
}

dt.print_log("created preset_list")

postsharpen.widgets["preset_update"] = dt.new_widget("button"){
  label = "update",
  clicked_callback = function ()
    update_preset()
  end
}

dt.print_log("created preset_update")

postsharpen.widgets["preset_delete"] = dt.new_widget("button"){
  label = "delete",
  clicked_callback = function() 
    delete_preset()
  end
}

dt.print_log("created preset_delete")

postsharpen.widgets["preset_new_name"] = dt.new_widget("entry"){
  tooltip = "specify the name of a new preset",
  text = "",
  placeholder = "Enter preset name",
  editable = true,
}

dt.print_log("created preset_delete")

postsharpen.widgets["preset_create"] = dt.new_widget("button"){
  label = "create",
  clicked_callback = function ()
    create_preset()
  end
}

dt.print_log("created preset_create")

postsharpen.widgets["presets"] = dt.new_widget("box"){
  orientation = "vertical",
  dt.new_widget("section_label"){label = "presets"},
  postsharpen.widgets["preset_list"],
--  postsharpen.widgets["preset_apply"],
  postsharpen.widgets["preset_update"],
  postsharpen.widgets["preset_delete"],
  dt.new_widget("separator"){},
  dt.new_widget("section_label"){label = "create preset"},
  postsharpen.widgets["preset_new_name"],
  postsharpen.widgets["preset_create"]
}

dt.print_log("created presets")

local widget_widgets = {postsharpen.widgets["output_path"], postsharpen.widgets["overwrite"], postsharpen.widgets["method_chooser"], postsharpen.widgets["method_stack"], postsharpen.widgets["presets"]}

-- let macos and windows users specify the location of the executabbles
if dt.configuration.running_os == "windows" or dt.configuration.running_os == "macos" then
  local engine_bins = {}
  for engine,v in pairs(postsharpen.engines) do
    table.insert(engine_bins, v['bin'])
  end
  dt.print_log("total engine bins is " .. #engine_bins)
  table.sort(engine_bins)
  dt.print_log("total engine bins after sorting is " .. #engine_bins)
  local uniq_bins = {}
  local lastval = ""
  for i = 1, #engine_bins do
    if engine_bins[i] ~= lastval then
      uniq_bins[#uniq_bins + 1] = engine_bins[i]
      lastval = engine_bins[i]
    end
  end
  dt.print_log("total uniq bins is " .. #uniq_bins)
  widget_widgets[#widget_widgets + 1] = df.executable_path_widget(uniq_bins)
end

dt.print_log("created widget_widgets")

local postsharpen_widget = dt.new_widget("box"){
  orientation = "vertical",
  dt.new_widget("label"){label = "output path"},
  table.unpack(widget_widgets),
}

dt.print_log("created postsharpen_widget")

apply_saved_preferences()

dt.print_log("applied save prefs")

-- register storage
dt.register_storage(
  "postsharpen",
  _("sharpen after export"), 
  show_status, 
  sharpen,
  nil, 
  setup, 
  postsharpen_widget
)

-- wait for the fun to begin