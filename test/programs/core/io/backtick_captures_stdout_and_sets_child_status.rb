# `` `cmd` `` lowers to a `Kernel#\`` fcall: it captures the child's
# stdout as a String and leaves the wait status in `$?`.

out = `echo hello`
print out
puts out.length
puts $?.exitstatus
puts $?.success?
puts $?.class
