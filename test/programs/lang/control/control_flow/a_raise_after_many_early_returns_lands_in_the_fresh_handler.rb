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

# A raise must land in this fresh handler, not a stale leaked frame.
begin
  sc[7]
  raise "boom"
rescue => e
  puts "caught #{e.message}"
end

