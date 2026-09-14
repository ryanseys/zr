#@ only: macos
# darwin's struct passwd has ten fields Etc::Passwd carries, in the order
# etc.c's setup_passwd gives them: the three past the shell are the
# password's change time, the login class and the account's expiry.
require "etc"
p Etc::Passwd.members
p Etc.getpwnam("root").to_a
pw = Etc.getpwuid
p [pw.change.class, pw.uclass.class, pw.expire.class, pw.to_a.size]

__END__
[:name, :passwd, :uid, :gid, :gecos, :dir, :shell, :change, :uclass, :expire]
["root", "*", 0, 0, "System Administrator", "/var/root", "/bin/sh", 0, "", 0]
[Integer, String, Integer, 10]
