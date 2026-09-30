# A method writes its params into an ivar Hash —
# `@data[key] = value` — and another method fills @data with String
# keys and values. No code calls the writer, and the program runs.

class T_ivar_hash_aset_param_widen_Bag
  def initialize
    @data = {}
  end

  # Fills @data with String keys and values.
  def populate(source)
    source.each do |k, v|
      @data[k] = v
    end
  end

  # No caller.
  def []=(key, value)
    @data[key] = value
  end

  def fetch(k)
    @data[k]
  end
end

b = T_ivar_hash_aset_param_widen_Bag.new
b.populate({ "x" => "hello" })
puts "ok"
puts b.fetch("x")
