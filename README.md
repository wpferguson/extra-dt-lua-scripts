# extra-dt-lua-scripts
Extra lua scripts for darktable that can't or wont be included in darktable-org/lua-scripts.

These scripts are dependent on the darktable-org/lua-scripts libraries, therefore the recommended
installation is:

* change directory to the darktable configuration directory 
  * ~/,config/darktable on linux and macos
  * ~/appdata/local/darktable on windows

* mkdir lua 
* cd lua 
* git clone https://github.com/darktable-org/lua-scripts.git 
* mkdir wpferguson
* cd wpferguson
* git clone https://github.com/wpferguson/extra-dt-lua-scripts 
* in your luarc 
  * require "wpferguson/_name of script_"


To update the scripts just change directory to the lua directory and do a 
**git pull**, then change to the wpferguson directory and do a **git pull** and 
everything should be up to date.
