require "etc"
p((Etc.confstr(-1) rescue $!.class), (Etc.sysconf(-1) rescue $!.class))
p((Etc.getgrgid("foo") rescue $!.class), (Etc.getgrgid(nil) rescue $!.class), (Etc.getpwuid(nil) rescue $!.class))
p((Etc.getgrnam(123) rescue $!.class), (Etc.getpwnam(nil) rescue $!.class))
p Etc.getpwuid.name == Etc.getpwuid(Process.uid).name
p((Etc.group { Etc.group { } } rescue $!), (Etc.passwd { Etc.passwd { } } rescue $!))
p Etc.group { break 1 }
