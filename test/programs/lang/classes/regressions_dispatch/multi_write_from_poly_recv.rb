# Multi-write `a, b = rhs` where rhs is an element of a nested
# structure that holds values of mixed classes. `a` gets the first
# element, an Array, so `a.length` works.

class T_multi_write_from_poly_recv_C
  def setup
    @h = {}
    [0, 1].each do |bank|
      [0, 1].each do |idx|
        # A Hash of Arrays of pairs of Arrays of two-tuples — same
        # shape as optcarrot's @lut_update.
        (((@h[bank] ||= [])[idx] ||= [nil, nil])[0] ||= []) << [idx * 10 + bank, idx + bank]
      end
    end
  end

  def name_lut_size(bank, idx)
    # Multi-write whose RHS is @h[bank][idx]: a Hash read, then an
    # Array read.
    name_lut_update, _attr_lut_update = @h[bank][idx]
    name_lut_update.length
  end
end

c = T_multi_write_from_poly_recv_C.new
c.setup
# bank=1 / idx=0 yields a 1-element list (one push at this slot).
puts c.name_lut_size(1, 0)
