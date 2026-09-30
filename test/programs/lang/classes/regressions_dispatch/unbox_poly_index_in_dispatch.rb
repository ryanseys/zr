# `arr[idx]`, where both `arr` and `idx` come from Hashes with values
# of mixed classes. Here `arr` is an Array and `idx` is an Integer.

class T_unbox_poly_index_in_dispatch_C
  def initialize
    @bag  = { "arr" => [100, 200, 300, 400], "lbl" => "x" }
    @keys = { "i" => 2, "s" => "lbl" }
  end
  def at(k)
    arr = @bag["arr"]      # an Array
    idx = @keys[k]         # an Integer
    arr[idx]               # Array#[] with an Integer index
  end
end

puts T_unbox_poly_index_in_dispatch_C.new.at("i").to_s    # 300
