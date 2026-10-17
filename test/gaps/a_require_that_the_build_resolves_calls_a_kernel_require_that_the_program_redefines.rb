# In ruby every require is a call of Kernel#require, so a program's own
# Kernel#require (bootsnap's, zeitwerk's) hears each one. zr compiles a
# literal require that its build resolves into the program: it calls the
# program's own require only when the same file defines it for the scope
# of the call (`Hir::Build::Loader#shadowed`).
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
