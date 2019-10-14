--[[
  copyright (c) 2018 - Bill Ferguson <wpferguson@gmail.com>

  correct_lens - non-destructively modify lens information used by darktable

  DESCRIPTION

  correct_lens provides a non-destructive way to correct the lens information used by darktable during image processing.

  When darktable imports an image it extracts certain information, including the lens identification string, from the image and inserts 
  it into the library database.  That database field is what darktable uses to display lens information and what the lens correction module 
  uses to determine what correction to apply.  If we update that field to the correct lens string, as used by lensfun, then the lens 
  correction module applies the correct correction and the image display module displays the correct information.

  correct_lens essentially builds a lookup table to translate from what the camera thinks the lens is, to what it actually is.  
  Once you've identified your lenses and the correct translation, then all that's left is to apply it to the images that need it.  

  I shoot with a Canon EOS 7D.  I have a Sigma 17-50mm f/2.8 lens.  When I take a picture the exif data shows that I used a 
  Canon EF-S 17-55mm f/2.8 IS USM.  I also have a Sigma 50-100mm f/1.8 Art lens.  The images identify it as Canon EF 28mm f/1.8 USM.  
  To fix this I install correct_lens.lua in my lua-scripts and enable it.  I go to a directory, or directories, with the mis-identified lenses 
  and select an image or images.  In the correct lens module I click the detect button.  The detected lenses appear in the text box.  
  After this I restart darktable so that I can add the corrected strings.  Once darktable is restarted I go the the correct lens module and 
  select the lens I want to change from the drop down list.  I enter the lens string from the lensfun database for my lens.  In the case of the 
  17-50mm it's Sigma 17-50mm f/2.8 EX DC OS HSM. Once I've entered it I click save to add it to the translation table.  If I accidently save 
  a bad translation, I can select it from the drop down and hit clear to remove it.  Once I've got my lens correction strings entered, 
  I go to a folder with mis-identified lenses.  I select the images and either click the apply button in the correct lens module or 
  click the correct lens information button in the selected images module.  _correct_lens.lua_ will check each selected image for the 
  offending lens string(s) and replace them if it's found.  If the string is not found, or there is no corrected string, the lens information 
  for the image remains unchanged.  A tag is added to the image noting what the original lens information was.  This is in case you want to 
  revert the changes.  This can be done by selecting the image(s) and clicking the revert button in the correct lens module.

  correct_lens is SLOW.  On my system it processes approximately 2 changed images per second.  This is because it's writing 
  each change to the database.  

  USAGE

  Select images with mis-identified lenses, then click the detect button in the correct lens module.  Restart darktable.  Select each 
  lens that needs the string corrected from the drop down.  Add the lens string for your lens as used in the lensfun database, then 
  click save.  Select the images you want to update and click apply.

  If for some reason you need to go back to the original information, select the images and click revert.

  NOTES

  This program modifies image information in your library.db file.  You might want to make a backup copy prior to using this script, 
  just to be on the safe side.  I haven't encountered any problems, other than my typing, but YMMV.

  It's **SLOW**.  I average 2 images per second.  I have a fast processor, lots of memory and an SSD.  Your performance might be worse.

  If you are modifying a lot of images (>100) then darktable will not respond while the images are updating.  I tried using a progress 
  bar and I tried writing messages to the screen, but the I/O is so heavy and the loop so tight that the progress bar and messages don't 
  update the screen.  When I'm doing a lot of images, I select them, then start the process, then I click on a single image.  When all the 
  images are updated, the single image will be selected so I know it's finished.

  Problems, ideas, etc., e-mail me at wpferguson@gmail.com
]]

--[[
  TODO: make lens available for use after detection
  TODO: make updates available as soon as they're made
  TODO: make image update a job
]]

local dt = require "darktable"
local du = require "lib/dtutils"
local gettext = dt.gettext

du.check_min_api_version("5.0.0", "correct_lens") 

-- Tell gettext where to find the .mo file translating messages for a particular domain
gettext.bindtextdomain("correct_lens",dt.configuration.config_dir.."/lua/locale/")

local function _(msgid)
    return gettext.dgettext("correct_lens", msgid)
end


local PS = dt.configuration.running_os == "windows" and "\\" or "/"

local correct_lens = {}

local function get_preferences(group)
  dt.print_log("looking for " .. group)
  local prefs = {}
  local DARKTABLERC = dt.configuration.config_dir .. PS .. "darktablerc"
  local f = io.open(DARKTABLERC, "r")
  if f then
    for line in f:lines() do
      if string.match(line, group) then
        dt.print_log("found match in " .. line)
        line = string.gsub(line, group .. "/", "")
        dt.print_log("line minus lua stuff is " .. line)
        local parts = du.split(line, "=")
        dt.print_log("found lens " .. parts[1])
        if not parts[2] then
          parts[2] = ""
        end
        prefs[parts[1]] = parts[2]
        dt.print_log("set prefs[" .. parts[1] .. "] = " .. parts[2])
      end
    end
    f:close()
  else
    dt.print_error("Unable to open " .. DARKTABLERC)
  end
  return prefs
end

local function set_correct_lens_preference(lens, correction)
  dt.preferences.write("correct_lens", lens, "string", correction)
end

local function get_correct_lens_preference(lens)
  return dt.preferences.read("correct_lens", lens, "string")
end

local function update_combobox_choices(combobox, choice_table, selected)
  local items = #combobox
  local choices = #choice_table
  if choices == 0 then
    return
  end
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

local function escape_lens_string(lens)
  lens = string.gsub(lens, "%-", "%%-")
  lens = string.gsub(lens, "%.", "%%.")
  return lens
end

local function stop_job(job)
  job.valid = false
end

local function apply_lens_string(images)
  if #images > 0 then
    --
    -- Make this a job
    --
    local job = dt.gui.create_job(_("images corrected"), true, stop_job)
    dt.print_log("created job")
    dt.print_log("lenses are " .. correct_lens.lenses)
    for i,image in ipairs(images) do
      if string.match(correct_lens.lenses, escape_lens_string(image.exif_lens)) then
       if correct_lens.lens_table[image.exif_lens]:len() > 0 then
          local tag_name = "correct_lens|original|" .. image.exif_lens
          local tag = dt.tags.create(tag_name)
          dt.tags.attach(tag, image)
          image.exif_lens = correct_lens.lens_table[image.exif_lens]
          dt.print_log("updated image " .. tostring(i))
        end
      end
      job.percent = i / #images
    end
    stop_job(job)
  else
    dt.print("no images selected")
  end
end

-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
--  main program
-- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 

correct_lens.stack = dt.new_widget("stack"){}

correct_lens.selector_values = {}

correct_lens.entries = {}

correct_lens.lens_table = get_preferences("lua/correct_lens")

correct_lens.lenses = ""

correct_lens.sorted_lenses = {}

dt.print_log("lens_table entries are " .. #correct_lens.lens_table)


for k,v in pairs(correct_lens.lens_table) do
  table.insert(correct_lens.sorted_lenses, k)
end

table.sort(correct_lens.sorted_lenses)

--if #correct_lens.sorted_lenses > 0 then

  count = 1
  for _,k in pairs(correct_lens.sorted_lenses) do
    local v = correct_lens.lens_table[k]
    dt.print_log("k is " .. k .. " and v is " .. v)
    correct_lens.lenses = correct_lens.lenses .. k .. "\n"
    correct_lens.selector_values[count] = k
    correct_lens.entries[count] = dt.new_widget("entry"){
      text = v,
      placeholder = "enter correct lens string",
      editable = true,
    }
    correct_lens.stack[count] = dt.new_widget("box"){
      correct_lens.entries[count],
      dt.new_widget("button"){
        label = "save",
        clicked_callback = function(self)
          dt.print_log("lens is " .. correct_lens.selector.value .. " and entry is " .. correct_lens.entries[correct_lens.selector.selected].text)
          set_correct_lens_preference(correct_lens.selector.value, correct_lens.entries[correct_lens.selector.selected].text)
          correct_lens.lens_table[correct_lens.selector.value] = correct_lens.entries[correct_lens.selector.selected].text
        end
      },
      dt.new_widget("button"){
        label = "clear",
        tooltip = "clear stored string correction",
        clicked_callback = function(self)
          set_correct_lens_preference(correct_lens.selector.value, "")
          correct_lens.entries[correct_lens.selector.selected].text = ""
          correct_lens[correct_lens.selector.value] = ""
        end
      },
    }
    count = count + 1
  end

  correct_lens.selector = dt.new_widget("combobox"){
    label = "select lens",
    tooltip = "select lens to modify",
    changed_callback = function(self)
      correct_lens.stack.active = self.selected
    end,
    value = 1, "No lenses detected",
  }

  if #correct_lens.selector_values > 0 then
    update_combobox_choices(correct_lens.selector, correct_lens.selector_values, 1)


    correct_lens.lenses = string.sub(correct_lens.lenses, 1, -2)

    dt.print_log("known lenses are " .. correct_lens.lenses)

    dt.print_log("stack entries are " .. #correct_lens.stack)

    correct_lens.stack[#correct_lens.stack + 1] = dt.new_widget("box"){ orientation = "vertical", dt.new_widget("label"){label = "test"}}
    dt.print_log("stack entries are " .. #correct_lens.stack)

  end

correct_lens.detected = dt.new_widget("text_view"){
  text = correct_lens.lenses,
  editable = false,
}

correct_lens.detect = dt.new_widget("button"){
  label = "detect lenses",
  tooltip = "get exif lens information from selected images",
  clicked_callback = function(self)
    if #dt.gui.action_images > 0 then
      local job = dt.gui.create_job(_("detect lenses"), true, stop_job)
      for i,image in ipairs(dt.gui.action_images) do
        lens = image.exif_lens
        if not string.match(correct_lens.detected.text, escape_lens_string(lens)) then
          dt.print_log("didn't find " .. lens .. " in " .. correct_lens.detected.text)
          dt.print_log("found new lens " .. lens)
          correct_lens.lens_table[lens] = get_correct_lens_preference(lens)
          local l = du.split(correct_lens.detected.text, "\n")
          dt.print_log("number of values in l is " .. #l)
          table.insert(l, lens)
          table.sort(l)
          if #l > 1 then
            dt.print_log("l values is " .. #l)
            correct_lens.detected.text = du.join(l, "\n")
          else
            correct_lens.detected.text = l[1]
          end
          local count = #correct_lens.entries
          local v = get_correct_lens_preference(lens)
          correct_lens.lenses = correct_lens.lenses .. lens .. "\n"
          correct_lens.selector_values[count+1] = lens
          -- create the entry
          correct_lens.entries[count + 1] = dt.new_widget("entry"){
            text = v,
            placeholder = "enter correct lens string",
            editable = true,
          }
          -- create the stack item
          correct_lens.stack[count+1] = dt.new_widget("box"){
            correct_lens.entries[count+1],
            dt.new_widget("button"){
              label = "save",
              clicked_callback = function(self)
                dt.print_log("lens is " .. correct_lens.selector.value .. " and entry is " .. correct_lens.entries[correct_lens.selector.selected].text)
                set_correct_lens_preference(correct_lens.selector.value, correct_lens.entries[correct_lens.selector.selected].text)
                correct_lens.lens_table[correct_lens.selector.value] = correct_lens.entries[correct_lens.selector.selected].text
              end
            },
            dt.new_widget("button"){
              label = "clear",
              tooltip = "clear stored string correction",
              clicked_callback = function(self)
                set_correct_lens_preference(correct_lens.selector.value, "")
                correct_lens.entries[correct_lens.selector.selected].text = ""
                correct_lens[correct_lens.selector.value] = ""
              end
            },
          }
          -- add the lens to the combobox
          update_combobox_choices(correct_lens.selector, correct_lens.selector_values, 1)
        end
        job.percent = i / #dt.gui.action_images
      end
      stop_job(job)
    else
      dt.print("No images selected")
      dt.print_error("no images selected for lens detection")
    end
  end
}

correct_lens.apply = dt.new_widget("button"){
  label = "apply",
  tooltip = "apply lens correction strings to selected images",
  clicked_callback = function(self)
    apply_lens_string(dt.gui.action_images)
  end
}

correct_lens.revert = dt.new_widget("button"){
  label = "revert",
  tooltip = "revert lens correction strings to original",
  clicked_callback = function(self)
    if #dt.gui.action_images > 0 then
      local job = dt.gui.create_job(_("images reverted"), true, stop_job)
      dt.print_log("have action_images")
      for i,image in ipairs(dt.gui.action_images) do
        local tags = dt.tags.get_tags(image)
        for _,t in ipairs(tags) do
          if string.match(t.name, "correct_lens|original|") then
            local tname = string.gsub(t.name, "correct_lens|original|", "")
            dt.tags.detach(t, image)
            image.exif_lens = tname
          end
        end
        job.percent = i / #dt.gui.action_images
      end
      stop_job(job)
    else
      dt.print("no images selected")
    end
  end
}

--if #correct_lens.sorted_lenses > 0 then
  correct_lens.widget = dt.new_widget("box"){
      orientation = "vertical",
      dt.new_widget("section_label"){ label = "known lenses" },
      correct_lens.detected,
      correct_lens.detect,
      dt.new_widget("section_label"){ label = "correct lens string" },
      correct_lens.selector,
      correct_lens.stack,
      dt.new_widget("section_label"){ label = "update selected images" },
      correct_lens.apply,
      correct_lens.revert,
  }
--else
--  correct_lens.widget = dt.new_widget("box"){
--      orientation = "vertical",
--      dt.new_widget("section_label"){ label = "known lenses" },
--      correct_lens.detected,
--      correct_lens.detect,
--  }
--end

-- register the lib


dt.register_lib(
  "correct_lens",     -- Module name
  "correct lens",     -- Visible name
  true,                -- expandable
  false,               -- resetable
  {[dt.gui.views.lighttable] = {"DT_UI_CONTAINER_PANEL_RIGHT_CENTER", 100}},   -- containers
  correct_lens.widget,
  nil,-- view_enter
  nil -- view_leave
)

--[[
    Add a button to the selected images module in lighttable
]]

dt.gui.libs.image.register_action(
  "correct lens information",
  function(event, images) apply_lens_string(images) end,
  "correct lens information"
)

--[[
    Add a shortcut
]]

dt.register_event(
  "shortcut",
  function(event, shortcut) apply_lens_string(dt.gui.action_images) end,
  "correct lens information"
)
