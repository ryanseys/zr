
# darwin's struct passwd has ten fields Etc::Passwd carries, in the order
# etc.c's setup_passwd gives them: the three past the shell are the
# password's change time, the login class and the account's expiry.
require "etc"
p Etc::Passwd.members
p Etc.getpwnam("root").to_a
pw = Etc.getpwuid
p [pw.change.class, pw.uclass.class, pw.expire.class, pw.to_a.size]

