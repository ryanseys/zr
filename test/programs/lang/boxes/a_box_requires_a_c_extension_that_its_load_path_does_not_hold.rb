# Ruby::Box#require of a C extension (digest/md5): the box gets the
# library's constants, a second require gives false, a feature that no
# file has raises LoadError, and a box in a forked child requires another
# one.
b = Ruby::Box.new
p b.require("digest/md5")
p b.eval("Digest::MD5.hexdigest('a')")
p b.require("digest/md5")
begin
  b.require("no/such/feature")
rescue LoadError => e
  p [e.class, e.message]
end
pid = fork { exit(Ruby::Box.new.require("digest/sha2") ? 0 : 1) }
p Process.wait2(pid)[1].success?
p Ruby::Box.new.require("digest/sha2")
