
# darwin's struct passwd has ten fields Etc::Passwd carries, in the order
# etc.c's setup_passwd gives them: the three past the shell are the
# password's change time, the login class and the account's expiry.
require "etc"
p Etc::Passwd.members
# root's shell is the machine's choice (/bin/sh, or /bin/bash on a CI
# runner), so the row gives only that it is a path.
root = Etc.getpwnam("root").to_a
p root.values_at(0, 1, 2, 3, 4, 5, 7, 8, 9), root[6].start_with?("/")
pw = Etc.getpwuid
p [pw.change.class, pw.uclass.class, pw.expire.class, pw.to_a.size]

