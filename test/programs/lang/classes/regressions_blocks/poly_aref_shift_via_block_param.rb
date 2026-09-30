# `a[idx]` goes into an Integer operator (`>>` / `<<` / ...)
# inside an `.each {|a| ... }` block, where `a` is an Array of mixed
# elements.
#
# `entries` here is one half of a destructured 2-tuple from a
# nested-ivar chain (`@store[bank][idx]`). `a[2]` is an Integer, so
# `data >> a[2]` is an Integer shift.

class T_poly_aref_shift_via_block_param_C
  def initialize
    # @store[bank][idx] is a 2-tuple: (names, entries).  Each entry
    # in `entries` is a [tag, payload, shift] triple, with elements
    # of mixed classes.
    @store = [[ [[1], [[10, [0, 1, 2], 4], [20, [3, 4, 5], 6]]] ]]
  end

  def run(bank, idx, data)
    _names, entries = @store[bank][idx]
    entries.each do |a|
      shifted = data >> a[2]
      puts shifted & 3
    end
  end
end

T_poly_aref_shift_via_block_param_C.new.run(0, 0, 0xff)
