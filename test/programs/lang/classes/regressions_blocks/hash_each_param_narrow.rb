# A class method whose only use of its Hash param is `h.each |k, v|`.
# The body joins `k` and `v` into a String with `+`, for a Hash with
# String values and for a Hash with Integer values.

class T_hash_each_param_narrow_Encoder
  def self.from_str_hash(h)
    out = "{"
    first = true
    h.each do |k, v|
      out += "," unless first
      first = false
      out += "\"" + k + "\":\"" + v + "\""
    end
    out + "}"
  end

  def self.from_int_hash(h)
    out = "{"
    first = true
    h.each do |k, v|
      out += "," unless first
      first = false
      out += "\"" + k + "\":" + v.to_s
    end
    out + "}"
  end
end

puts T_hash_each_param_narrow_Encoder.from_str_hash({"name" => "alice", "city" => "NYC"})
puts T_hash_each_param_narrow_Encoder.from_int_hash({"a" => 1, "b" => 2, "c" => 3})
