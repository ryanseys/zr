# etc_each_passwd and etc_each_group return the class after a block, also
# where etc is required by a file compiled at run time.
require "etc"
p [Etc::Passwd.each { }.equal?(Etc::Passwd), Etc::Passwd.each.class, Etc::Group.each { }.equal?(Etc::Group)]
load File.join(Dir.pwd, "late" + ".rb")
