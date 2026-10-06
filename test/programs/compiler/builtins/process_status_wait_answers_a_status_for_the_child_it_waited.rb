# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

pid = Process.spawn("true")
st = Process::Status.wait(pid)
puts "Status.wait: #{st.class}"
puts "Status.wait exit: #{st.exitstatus}"
puts "Status coredump?: #{st.coredump?}"
puts "Status stopsig: #{st.stopsig.inspect}"

