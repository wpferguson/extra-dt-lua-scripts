--[[

    dxo_photolab.lua - edit an image with DxO.PhotoLab and import the result

    Copyright (C) 2018 Bill Ferguson <wpferguson@gmail.com>.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]
--[[
    dxo_photolab - open a image in darktable with dxo_photolab for editing

    This script provides another storage (export target) for darktable.  The names of 
    the selected files are assembled into a list and DxO.PhotoLab is invoked with the list
    of images.  After editing with DxO.PhotoLab, the result is saved to the darktable
    image directory.  When DxO.PhotoLab exits, the result files are imported and grouped with
    the original files.

    ADDITIONAL SOFTWARE NEEDED FOR THIS SCRIPT
    * dxo_photolab - http://www.dxo.com

    USAGE
    * require this script from your main lua file
    * select an image or images for processing with DxO.PhotoLab
    * in the export dialog select "dxo_photolab"
    * specify the location of the DxO.PhotoLab executable it isn't showing
    * Press "export"
    * Edit the image with DxO.PhotoLab then export the result
    * Exit DxO.PhotoLab
    * The resulting image(s) will be imported and grouped with the original image

    CAVEATS
    * DxO.PhotoLab only runs on windows and macos.  It does not currently run under wine.

    BUGS, COMMENTS, SUGGESTIONS
    * Send to Bill Ferguson, wpferguson@gmail.com

    CHANGES
]]

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"
require "official/yield"
local gettext = dt.gettext
local dxo_photolab_widget = nil

du.check_min_api_version("5.0.0")

if du.check_os({"windows","macos"}) then

  -- Tell gettext where to find the .mo file translating messages for a particular domain
  gettext.bindtextdomain("dxo_photolab",dt.configuration.config_dir.."/lua/locale/")

  local function _(msgid)
      return gettext.dgettext("dxo_photolab", msgid)
  end

  local function sanitize_filename(filepath)
    local path = df.get_path(filepath)
    local basename = df.get_basename(filepath)
    local filetype = df.get_filetype(filepath)

    local sanitized = string.gsub(basename, " ", "\\ ")

    return path .. sanitized .. "." .. filetype
  end

  local function show_status(storage, image, format, filename,
    number, total, high_quality, extra_data)
      dt.print(string.format(_("Export Image %i/%i"), number, total))
  end

  local function dxo_photolab_edit(storage, image_table, extra_data) --finalize

    local dxo_photolab_executable = df.check_if_bin_exists("dxo_photolab")

    if not dxo_photolab_executable then
      dt.print_error(_("DxO.PhotoLab not found"))
      return
    end

    -- list of exported images
    local img_list

     -- reset and create image list
    img_list = ""
    img_path = ""

    for raw_img,exp_img in pairs(image_table) do
      exp_img = sanitize_filename(exp_img)
      os.remove(exp_img)  -- we don't need the exported files, so just remove them
      img_list = img_list .. "\"" .. raw_img.path  .. "/" .. raw_img.filename .. "\"" .. " "
      img_path = "\"" .. raw_img.path .. "\""
    end
    dt.print_log("image path is " .. img_path)

    dt.print(_("Launching DxO.PhotoLab..."))

    local dxo_photolab_start_command
    dxo_photolab_start_command = dxo_photolab_executable .. " -mode=openwith " .. img_list

    dt.print_log("dxo start command is " .. dxo_photolab_start_command)

    dt.control.execute( dxo_photolab_start_command)

    dt.database.import(img_path)

  end

  -- Register

  dxo_photolab_widget = df.executable_path_widget({"dxo_photolab"})

  dt.register_storage("module_dxo_photolab", _("dxo_photolab"), show_status, dxo_photolab_edit, nil, nil, dxo_photolab_widget)

  --
else
  dt.print("dxo_photolab does not work on " .. dt.configuration.running_os)
  return
end
