# fetch and dup on a hash with mixed keys and mixed values. Two
# writers to the same ivar use keys of different types (a param
# and a Symbol literal), so the hash holds both kinds of key.

module M
  @h = {}

  def self.write1(k, v)
    @h[k] = v
  end

  def self.write2(v)
    @h[:special] = v
  end

  def self.read(k)
    @h.fetch(k, nil)
  end
end

M.write2("hello")
puts M.read(:special)
puts M.read(:missing).nil?
