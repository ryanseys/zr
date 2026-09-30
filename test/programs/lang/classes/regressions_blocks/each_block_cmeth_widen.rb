# A class method called with the `k` and `v` of `h.each { |k, v| }`
# gets the Hash's String keys and values as its argument.

class T_each_block_cmeth_widen_Json
  def self.escape(s)
    out = ""
    i = 0
    n = s.length
    while i < n
      out = out + s[i]
      i += 1
    end
    out
  end

  def self.from_str_hash(h)
    out = "{"
    h.each do |k, v|
      out = out + "\"" + T_each_block_cmeth_widen_Json.escape(k) + "\":\"" + T_each_block_cmeth_widen_Json.escape(v) + "\""
    end
    out + "}"
  end
end

puts T_each_block_cmeth_widen_Json.from_str_hash({"a" => "b"})
puts T_each_block_cmeth_widen_Json.from_str_hash({"x" => "y"})
