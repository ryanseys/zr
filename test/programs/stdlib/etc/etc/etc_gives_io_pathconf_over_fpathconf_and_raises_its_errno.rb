# etc gives IO#pathconf: fpathconf(3) on the stream's descriptor.
p IO.method_defined?(:pathconf)
require "etc"
p File.open("/") { |f| f.pathconf(Etc::PC_NAME_MAX) }.class, IO.pipe { |r, _| r.pathconf(Etc::PC_PIPE_BUF) }.positive?
p (File.open("/") { |f| f.pathconf(99999) } rescue $!), (File.open("/") { |f| f.pathconf("x") } rescue $!)
p IO.instance_method(:pathconf).owner
