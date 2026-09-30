# The pike VM's scratch state -- the visited array and the two thread lists --
# is cached on the compiled PATTERN to avoid a malloc per match, behind a
# re-entrancy flag. A pattern is shared by every thread matching against it, so
# two threads must not take the same scratch arrays: scan, gsub, match, sub and
# split in each thread give the same result as in the main thread.
TEXT = "the quick brown fox jumps over the lazy dog"
E_SCAN  = TEXT.scan(/[a-z]+/)
E_GSUB  = TEXT.gsub(/[aeiou]/, "-")
E_MATCH = TEXT.match(/(\w+) (\w+)/)[2]
E_SUB   = TEXT.sub(/quick/, "slow")
E_SPLIT = TEXT.split(/\s+/).length

threads = 4.times.map do
  Thread.new do
    bad = 0
    300.times do
      bad += 1 if TEXT.scan(/[a-z]+/) != E_SCAN
      bad += 1 if TEXT.gsub(/[aeiou]/, "-") != E_GSUB
      bad += 1 if TEXT.match(/(\w+) (\w+)/)[2] != E_MATCH
      bad += 1 if TEXT.sub(/quick/, "slow") != E_SUB
      bad += 1 if TEXT.split(/\s+/).length != E_SPLIT
      bad += 1 unless TEXT =~ /brown/
    end
    bad
  end
end

p threads.map(&:value).sum
p E_SCAN.length
p E_GSUB
