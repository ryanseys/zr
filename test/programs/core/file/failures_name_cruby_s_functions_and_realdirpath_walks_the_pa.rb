# Each failure names the C function that CRuby names, and realdirpath
# and a realpath past a file walk the path as realpath_rec does.
[-> { File::Stat.new("/nonexistent") }, -> { File.ftype("/nonexistent") }, -> { File.mkfifo("/nonexistent/x") },
 -> { File.realdirpath("/tmp/nonexist_zz/x") }, -> { File.realpath("/tmp/nonexist_zz") }, -> { File.realpath("/etc/hosts/x") },
 -> { File.realdirpath("/etc/hosts/x") }].each { |call| p((call.call rescue $!)) }
p File.realdirpath("/tmp/zz_none"), File.realdirpath("zz_none", "/tmp"), File.realdirpath("/")
p File.birthtime(__FILE__) == File.ctime(__FILE__), File.stat(__FILE__).birthtime.class
