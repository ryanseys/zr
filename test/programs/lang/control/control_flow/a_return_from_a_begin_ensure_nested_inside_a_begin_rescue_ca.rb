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

# Return from a begin..ensure nested inside begin/rescue: after the ensure
# runs, the deferred return must also pop the enclosing rescue frame.
def ensure_in_rescue(flag)
  begin
    begin
      return "early2" if flag
      "body"
    ensure
      $ensure_runs2 += 1
    end
  rescue
    "rescued"
  end
end

$ensure_runs2 = 0
200.times { ensure_in_rescue(true) }
puts $ensure_runs2
begin
  raise "after ensure 2"
rescue => e
  puts "caught #{e.message}"
end
puts "done"
