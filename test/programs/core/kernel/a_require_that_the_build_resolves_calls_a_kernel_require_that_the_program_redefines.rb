# In ruby each require is a call of `require` on self, so a program's own
# Kernel#require (bootsnap's, zeitwerk's) hears each one, also of a file
# that zr compiles in, and the file loads through that method's alias.
# rubygems loads its own files as it needs them; ruby has them before
# the first line.
Gem::Specification.stubs
module Kernel
  alias plain_require require
  def require(name)
    puts "require #{name}"
    plain_require(name)
  end
  private :require
end
p require("set")
p require("rbconfig")
p require("shellwords")
p require("shellwords")
p Shellwords.escape("a b")
# A bundled gem's file loads through it too.
p require("abbrev"), "car".then { %w[car cat].abbrev.keys.size }
