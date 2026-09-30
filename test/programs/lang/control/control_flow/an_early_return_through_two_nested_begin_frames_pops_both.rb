# An early `return` from inside begin/rescue must pop the live exception
# frames it exits. Otherwise the next raise lands in a handler that is gone
# (as in the SoundManager#[] of Doom), and repeated calls overflow the
# exception stack.

class SoundCache
  def initialize
    @cache = {}
  end

  def [](key)
    begin
      return @cache[key] if @cache.key?(key)
      value = key * 2
      @cache[key] = value
      value
    rescue
      -1
    end
  end
end

sc = SoundCache.new
sc[7]  # populate: the non-early path pops its frame correctly

# Early return through two nested begin frames pops both.
def double_nested(flag)
  begin
    begin
      return "inner-out" if flag
      "no"
    rescue
      "r1"
    end
    "outer"
  rescue
    "r2"
  end
end

200.times { double_nested(true) }
puts double_nested(true)
begin
  raise "deep"
rescue => e
  puts "caught #{e.message}"
end

