# Every Enumerable method that answers one element an element hands
# its enumerator the receiver's own count, so `size` answers without
# walking anything (enum.c, `enum_size`). A receiver with no count to
# give leaves the enumerator's unknown.
r = (1..4)
%i[map collect select filter find_all reject filter_map flat_map
   collect_concat partition group_by sort_by min_by max_by minmax_by
   each_with_index reverse_each each_entry chunk].each do |name|
  print r.public_send(name).size
end
puts
p r.each_with_object([]).size

class Sizeless
  include Enumerable
  def each = block_given? ? (yield 1) : to_enum(:each)
end
p Sizeless.new.map.size
