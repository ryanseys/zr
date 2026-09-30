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

# Return from a begin/rescue nested inside begin..ensure: the deferred
# return must pop down to the frame depth at ensure entry (both the rescue
# frame and the ensure frame), then run the ensure.
def rescue_in_ensure(flag)
  begin
    begin
      return "early" if flag
      "body"
    rescue
      "rescued"
    end
  ensure
    $ensure_runs += 1
  end
end

$ensure_runs = 0
200.times { rescue_in_ensure(true) }
puts $ensure_runs
begin
  raise "after ensure"
rescue => e
  puts "caught #{e.message}"
end

