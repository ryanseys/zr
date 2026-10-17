# RbConfig.ruby is the interpreter that runs the program, and it is
# `bindir` plus `ruby_install_name` and EXEEXT, so a library that builds
# the path from the parts (test-all's test_notfound, rubygems'
# exec_format) gets the same command.
config = RbConfig::CONFIG
p RbConfig.ruby == File.join(config["bindir"], config["ruby_install_name"] + config["EXEEXT"])
p config["RUBY_INSTALL_NAME"] == config["ruby_install_name"]
p File.executable?(RbConfig.ruby)
p RbConfig.expand(+"$(bindir)/$(ruby_install_name)") == File.join(config["bindir"], config["ruby_install_name"])
