# `arr[start, len] = src` slice-assign where `src` came from
# `.first` (or `.last`) of an Array of Integer Arrays. The slice
# assign puts the elements of `src` in place. It does not do
# `arr[start] = len`.

class T_intarray_slice_assign_from_intarray_ptr_array_first_C
  def initialize
    buf = (0...32).to_a
    @banks = (0...2).map { buf.slice!(0, 8) }
    @ref = [0] * 24
    @ref[5, 8] = @banks.first
    @ref[15, 8] = @banks.last
  end

  def show
    @ref.each { |x| print x, " " }
    puts
  end
end

T_intarray_slice_assign_from_intarray_ptr_array_first_C.new.show
