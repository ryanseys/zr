# A popen stream waits for its child when it closes. A child that the
# block already waited for leaves `$?` cleared, and the close raises
# nothing.
IO.popen(["/bin/echo", "hi"]) do |io|
  p io.read
  p Process.waitpid(io.pid) == io.pid
  p $?.exitstatus
end
p $?

IO.popen(["/bin/echo", "again"], &:read)
p $?.exitstatus
