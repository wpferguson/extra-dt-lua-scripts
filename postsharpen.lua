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
    Presets
]]

-- TODO: Add filename conflict resolution [overwrite|unique]

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
  widgets = {}

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
  local v = dt.preferences.read(MODULE_NAME, name, datatype)
  if not v then v = value end
  return dt.new_widget("slider"){
    label = label,
    tooltip = tooltip,
    soft_min = smin,
    soft_max = smax,
    hard_min = hmin,
    hard_max = hmax,
    step = step,
    digits = digits,
    value = v,
  }
end

local function create_preset(name)
  -- create a preset
end

local function update_preset(preset)
  -- update an existing preset
end

local function delete_preset(preset)
  -- delete a preset
end

local function rename_preset(preset, new_name)
  -- rename an existing preset
end

local function apply_preset(preset)
  -- configure the settings from a preset
end

local function read_presets()
  -- read the presets from preferences
end

local function save_presets()
  -- save the presets to preferences
end

local function default_presets()
  -- a set of default presets, if none exist
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
end

local function setup(storage, img_format, image_table, high_quality, extra_data)
  -- set up for the export
  -- save widget values in the extra_data table
  extra_data["images"] = image_table
  extra_data["output_path"] = postsharpen.widgets["output_path"].text
  dt.preferences.write(MODULE_NAME, "output_path", "string", postsharpen.widgets["output_path"].text)
  extra_data["method"] = postsharpen.widgets["method_chooser"].value
  dt.preferences.write(MODULE_NAME, "method_chooser", "integer", postsharpen.widgets["method_chooser"].selected)
  extra_data["sharpen_sigma"] = postsharpen.widgets["sharpen_sigma"].value
  dt.preferences.write(MODULE_NAME, "sharpen_sigma", "float", postsharpen.widgets["sharpen_sigma"].value)
  extra_data["sharpen_radius"] = postsharpen.widgets["sharpen_radius"].value
  dt.preferences.write(MODULE_NAME, "sharpen_radius", "integer", postsharpen.widgets["sharpen_radius"].value)
  extra_data["unsharp_radius"] = postsharpen.widgets["unsharp_radius"].value
  dt.preferences.write(MODULE_NAME, "unsharp_radius", "float", postsharpen.widgets["unsharp_radius"].value)
  extra_data["unsharp_sigma"] = postsharpen.widgets["unsharp_sigma"].value
  dt.preferences.write(MODULE_NAME, "unsharp_sigma", "float", postsharpen.widgets["unsharp_sigma"].value)
  extra_data["unsharp_amount"] = postsharpen.widgets["unsharp_amount"].value / 100.
  dt.preferences.write(MODULE_NAME, "unsharp_amount", "integer", postsharpen.widgets["unsharp_amount"].value)
  extra_data["unsharp_threshold"] = postsharpen.widgets["unsharp_threshold"].value / 100.
  dt.print_log("unsharp_threshold is " .. postsharpen.widgets["unsharp_threshold"].value)
  dt.preferences.write(MODULE_NAME, "unsharp_threshold", "integer", postsharpen.widgets["unsharp_threshold"].value)
  extra_data["filetype"] = img_format.extension
  dt.print_log("image format is " .. img_format.extension)
end

local function sharpen(storage, image_table, extra_data)
  -- sharpen the exported images
  local images = extra_data["images"]
  local sharpen_opts = string.format(" %dx%.02f ", extra_data["sharpen_radius"], extra_data["sharpen_sigma"])
  dt.print_log("sharpen_opts are " .. sharpen_opts)
  local unsharp_opts = string.format(" %.02fx%.02f+%.02f+%.02f ", extra_data["unsharp_radius"], extra_data["unsharp_sigma"], extra_data["unsharp_amount"], 
                                               extra_data["unsharp_threshold"])
  dt.print_log("unsharp_opts are " .. unsharp_opts)
  local datetime = os.date("*t")
  local convert = df.check_if_bin_exists("convert")
  dt.print_log("method is " .. extra_data["method"])
  local sharpen_cmd = extra_data["method"] == "sharpen" and convert .. " -sharpen" .. sharpen_opts or convert .. " -unsharp" .. unsharp_opts
  dt.print_log("sharpen command is " .. sharpen_cmd)
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
    local filename = image_table[image]
    dt.print_log("running " .. sharpen_cmd .. filename .. " " .. destination)
    dtsys.external_command(sharpen_cmd .. filename .. " " .. destination)
    os.remove(filename)
    job.percent = i / #images
  end
  stop_job(job)
--  local result = dtsys.external_command(sharpen_cmd .. df.get_path(destination) .. PS .. "*." .. extra_data["filetype"])
end

-- - - - - - - - - - - - - - - - - - - - - - - -
-- M A I N
-- - - - - - - - - - - - - - - - - - - - - - - -

-- read my stored data

-- set up widgets

-- sharpen widgets

-- radius

postsharpen.widgets["sharpen_radius"] = create_slider(_("radius"), _("the extent of the effect, leave at 0 to let the program choose the best value"), 
                                                      0, 5, 0, 5, 1, 0, "sharpen_radius", "integer", 0)

-- sigma

postsharpen.widgets["sharpen_sigma"] = create_slider((_"sigma"), _("the amount of sharpening"), 
                                                     0, 5, 0, 5, 0.1, 1, "sharpen_sigma", "float", .75)
-- unsharp widgets

-- radius

postsharpen.widgets["unsharp_radius"] = create_slider(_("radius"), _("the radius of the Gaussian, in pixels, not counting the center pixel"),
                                                      0, 5, 0, 5, 0.1, 1, "unsharp_radius", "float", 0.2)

-- sigma

postsharpen.widgets["unsharp_sigma"] = create_slider(_("sigma"), _("the standard deviation of the Gaussian, in pixels.  Should be >= radius"), 
                                                       0, 5, 0, 5, 0.1, 1, "unsharp_sigma", "float", 0.2)

-- amount

postsharpen.widgets["unsharp_amount"] = create_slider(_("amount"), _("the percentage of the difference between the original and the blur image that is added back into the original"), 
                                                      0, 500, 0, 500, 1, 0, "unsharp_amount", "integer", 100)

-- threshold

postsharpen.widgets["unsharp_threshold"] = create_slider(_("threshold"), _("the threshold to limit the effect.  0 is full effect and 100 is no effect"),
                                                         0, 100, 0, 100, 1, 0, "unsharp_threshold", "integer", 25)

local tmp = dt.preferences.read(MODULE_NAME, "output_path", "string")
if string.len(tmp) < 1 then tmp = "$(FILE_FOLDER)/darktable_exported/$(FILE_NAME)" end
postsharpen.widgets["output_path"] = dt.new_widget("entry"){
  text = tmp,
  editable = true,
}

postsharpen.widgets["unsharp_widget"] = dt.new_widget("box"){
  orientation = "vertical",
  dt.new_widget("label"){label = _("unsharp mask")},
  postsharpen.widgets["unsharp_radius"],
  postsharpen.widgets["unsharp_sigma"],
  postsharpen.widgets["unsharp_amount"],
  postsharpen.widgets["unsharp_threshold"],
}

postsharpen.widgets["sharpen_widget"] = dt.new_widget("box"){
  orientation = "vertical",
  dt.new_widget("label"){label = _("sharpen")},
  postsharpen.widgets["sharpen_sigma"],
  postsharpen.widgets["sharpen_radius"],
}

postsharpen.widgets["method_stack"] = dt.new_widget("stack"){
  postsharpen.widgets["unsharp_widget"],
  postsharpen.widgets["sharpen_widget"],
}

tmp = dt.preferences.read(MODULE_NAME, "method_chooser", "integer")
if tmp <= 0 then tmp = 1 end
postsharpen.widgets["method_chooser"] = dt.new_widget("combobox"){
  label = _("method"),
  tooltip = _("select sharpening method"),
  changed_callback = function(self)
    postsharpen.widgets["method_stack"].active = self.selected
  end,
  value = tmp, _("unsharp mask"),_("sharpen"),
}

local postsharpen_widget = dt.new_widget("box"){
  orientation = "vertical",
  dt.new_widget("label"){label = "output path"},
  postsharpen.widgets["output_path"],
  postsharpen.widgets["method_chooser"],
  postsharpen.widgets["method_stack"],
}
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