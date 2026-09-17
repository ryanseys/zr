# A timeout stops a match that backtracks without end (a backreference
# keeps Onigmo's match cache out), whichever method started it; a
# pattern the cache makes linear finishes inside the same limit.

slow = Regexp.new('\A(a|aa)*\1\z', timeout: 0.05)
text = "a" * 64 + "!"
{
  "match" => -> { slow.match(text) },
  "match?" => -> { slow.match?(text) },
  "===" => -> { slow === text },
  "=~" => -> { slow =~ text },
  "scan" => -> { text.scan(slow) },
  "gsub" => -> { text.gsub(slow, "") },
  "split" => -> { text.split(slow) },
  "index" => -> { text.index(slow) },
}.each do |name, run|
  run.call
  p [name, :finished]
rescue Regexp::TimeoutError => e
  p [name, e.class, e.message]
end

fast = Regexp.new('\A(a+)+\z', timeout: 0.5)
p fast.match?("a" * 5000 + "b")

__END__
["match", Regexp::TimeoutError, "regexp match timeout"]
["match?", Regexp::TimeoutError, "regexp match timeout"]
["===", Regexp::TimeoutError, "regexp match timeout"]
["=~", Regexp::TimeoutError, "regexp match timeout"]
["scan", Regexp::TimeoutError, "regexp match timeout"]
["gsub", Regexp::TimeoutError, "regexp match timeout"]
["split", Regexp::TimeoutError, "regexp match timeout"]
["index", Regexp::TimeoutError, "regexp match timeout"]
false
