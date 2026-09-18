# A feature ruby carries and this runtime has no file for. The require is
# not refused where it is written: it becomes a stop, which says what it
# was and where when the program runs it. A guarded one the program never
# reaches costs it nothing, which is why `mkmf` here does not stop this
# file from compiling.
if ARGV.include?("--build-extension")
  require "mkmf"
  p have_header("stdio.h")
end
p :compiled
