# extra-dt-lua-scripts
Extra lua scripts for darktable that can't, wont, or aren't ready to be included in darktable-org/lua-scripts.

These scripts are dependent on the darktable-org/lua-scripts libraries. They need the darktable-org/lua-scripts respository
installed.  Instructions for installing can be found at https://github.com/darktable-org/lua-scripts/README.md

## Install

### Linux/MacOS

    cd ~/.config/darktable/lua
    git clone https://github.com/wpferguson/extra-dt-lua-scripts wpferguson

### Windows

    cd %LOCALAPPDATA%\darktable\lua
    git clone https://github.com/wpferguson/extra-dt-lua-scripts wpferguson

## Enable

Add a line to the luarc `require "wpferguson/<name of script>"`.

If you are using script_manager to manage your scripts, then you will see a new category, wpferguson.  Select that and enable/disable the scripts that you want to use.

## Update

Open terminal and change directory to the wpferguson directory.  Do a `git pull`.

## Scripts

### Can't/Wont

These scripts were either rejected because they weren't found suitable to be included in the repository, or can't be included because they enable the use of non-free software.

Name|Standalone|OS   |Purpose
----|:--------:|:---:|-------
export2collection|Yes|LMW|Export an image, then import the result and group with the original.
dxo_photolab|No| MW|Export a file to DXO Photolab for editing and import the result and group with the original.

### Work in Progress

These scripts are works in progress.  I use them, but they aren't completely finished or ready for inclusion in the darktable-org/lua-scripts repository.  They work for me, but you mileage may vary.

Name|Standalone|OS   |Purpose
----|:--------:|:---:|-------
adjust_time|Yes|LMW|Adjust image times to synchronize images taken from multiple cameras for one event
correct_lens|Yes|LMW|Alter the image database lens information string to correct for unknown or incorrectly recognized lenses
postsharpen|No|LMW|Sharpen images after export using imagemagick

