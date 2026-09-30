# `attr_accessor :foo` with no `initialize`-time assignment must
# read as nil before any write, so `"[#{a.counter}]"` renders `[]`,
# as in MRI.
#
# `b.counter = 0` on a sibling instance sets that instance only. The
# unset `a.counter` read on a fresh `T_uninit_attr_accessor_reads_as_nil_A.new` still returns nil.

class T_uninit_attr_accessor_reads_as_nil_A
  attr_accessor :counter
end

a = T_uninit_attr_accessor_reads_as_nil_A.new
puts "[#{a.counter}]"

b = T_uninit_attr_accessor_reads_as_nil_A.new
b.counter = 0
puts "[#{b.counter}]"

# Shape with attr_reader-only (no writer at all).
class T_uninit_attr_accessor_reads_as_nil_Box
  attr_reader :tag
end

box = T_uninit_attr_accessor_reads_as_nil_Box.new
puts "tag=[#{box.tag}]"
