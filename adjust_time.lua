--[[

    adjust_time.lua - synchronize image time for images shot with different cameras

    Copyright (C) 2019 Bill Ferguson <wpferguson@gmail.com>.

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
    adjust_time - non-destructively modify the image time

    DESCRIPTION

    I recently purchased a 7DmkII to replace my aging 7D.  My 7D was still
    serviceable, so I bought a remote control and figured I'd try shooting
    events from 2 different perspectives.  I didn't think to synchonize the 
    time between the 2 cameras, so when I loaded the images and sorted by
    time it was a disaster.  I hacked a script together with hard coded values
    to adjust the exif_datetime_taken value in the database for the 7D images 
    so that everything sorted properly.  I've tried shooting with 2 cameras 
    several times since that first attempt.  I've gotten better at getting the
    camera times close, but still haven't managed to get them to sync.  So I
    decided to think the problem through and write a proper script to take 
    care of the problem.

    USAGE

    Select 2 images, one from each camera, of the same moment in time.  Click
    the Calculate button to calculate the time difference.  The difference is
    displayed in the difference entry.  You can manually adjust it by changing
    the value if necessary.

    Select the images that need their time adjusted.  Determine which way to adjust
    adjust the time (add or subtract) and click the appropriate button.

    If the image times get messed up and you just want to start over, select all 
    the images and click remove in the selected images module.  Reimport the folder
    and the time information will be that of the image.

    NOTES

    This program can also just adjust image times.  Say for instance your camera
    was set for daylight savings time and you didn't change it when the time changed.
    You can select 2 adjacent images and calculate the difference.  The difference
    in seconds is displayed.  You can change that value to 3600 (number of seconds
    in an hour), then select all the mistimed images, and add or subtract it to correct 
    the time.

    BUGS, COMMENTS, SUGGESTIONS
    * Send to Bill Ferguson, wpferguson@gmail.com

    CHANGES

    TODO

    better feedback
    translation

]]
local dt = require "darktable"
local du = require "lib/dtutils"
local gettext = dt.gettext

local adj_time = {}

du.check_min_api_version("3.0.0", "adjust_time") 


-- Tell gettext where to find the .mo file translating messages for a particular domain
gettext.bindtextdomain("adjust_time",dt.configuration.config_dir.."/lua/locale/")

local function _(msgid)
    return gettext.dgettext("adjust_time", msgid)
end

-- function to convert from exif time to system time
local function exiftime2systime(image)
  local yr,mo,dy,h,m,s = string.match(image.exif_datetime_taken, "(%d-):(%d-):(%d-) (%d-):(%d-):(%d+)")
  return(os.time{year=yr, month=mo, day=dy, hour=h, min=m, sec=s})
end

-- function to convert from systime to exif time
local function systime2exiftime(systime)
  local t = os.date("*t", systime)
  return(string.format("%4d:%02d:%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.min, t.sec))
end

local function calc_time_difference(image1, image2)
  return math.abs(exiftime2systime(image1) - exiftime2systime(image2))
end

local function adjust_image_time(image, difference)
  image.exif_datetime_taken = systime2exiftime(exiftime2systime(image) + difference)
  return
end

local function calculate_difference(images)
  if #images == 2 then
    adj_time.diff_entry.text = calc_time_difference(images[1], images[2])
    adj_time.subtract_btn.sensitive = true
    adj_time.add_btn.sensitive = true
  else
    dt.print("Error: 2 images must be selected")
  end
end

local function adjust_times(images, difference)
  for _, image in ipairs(images) do
    adjust_image_time(image, difference)
  end
end

local function subtract_time(images)
  adjust_times(images, tonumber(adj_time.diff_entry.text) * -1)
end

local function add_time(images)
  adjust_times(images, tonumber(adj_time.diff_entry.text))
end

-- widgets

adj_time.diff_entry = dt.new_widget("entry"){
  tooltip = "Time difference between images in seconds",
  placeholder = "Select 2 images and use the calculate button",
  text = "",
}

adj_time.calc_btn = dt.new_widget("button"){
  label = "Calculate",
  tooltip = "calculate time difference between 2 images",
  clicked_callback = function()
    calculate_difference(dt.gui.action_images)
  end
}

adj_time.subtract_btn = dt.new_widget("button"){
  label = "Subtract Difference",
  tooltip = "subtract the time difference from selected images",
  sensitive = false,
  clicked_callback = function()
    subtract_time(dt.gui.action_images)
  end
}

adj_time.add_btn = dt.new_widget("button"){
  label = "Add Difference",
  tooltip = "add the time difference to selected images",
  sensitive = false,
  clicked_callback = function()
    add_time(dt.gui.action_images)
  end
}

adj_time.widget = dt.new_widget("box"){
  orientation = "vertical",
  dt.new_widget("label"){label = "Time Difference"},
  adj_time.diff_entry,
  adj_time.calc_btn,
  dt.new_widget("separator"){},
  adj_time.add_btn,
  adj_time.subtract_btn,
}

dt.register_lib(
  "adjust_time",     -- Module name
  "adjust time",     -- Visible name
  true,                -- expandable
  false,               -- resetable
  {[dt.gui.views.lighttable] = {"DT_UI_CONTAINER_PANEL_RIGHT_CENTER", 100}},   -- containers
  adj_time.widget,
  nil,-- view_enter
  nil -- view_leave
)
