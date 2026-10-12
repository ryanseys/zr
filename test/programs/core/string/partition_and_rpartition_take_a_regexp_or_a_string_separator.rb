# String#partition and #rpartition take a Regexp, or a String (what
# to_str gives) as text, as get_pat_quoted does. Anything else is
# "wrong argument type X (expected Regexp)". Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

class Sep
  def to_str = "-"
end
[:a, nil, 1, 1.5, [], Sep.new, "-", /-+/].each do |sep|
  shown = sep.is_a?(Sep) ? "Sep" : sep.inspect
  try("partition(#{shown})") { "a--b-c".partition(sep) }
  try("rpartition(#{shown})") { "a--b-c".rpartition(sep) }
end
try("partition no match") { "abc".partition("z") }
try("rpartition no match") { "abc".rpartition(/z/) }
try("partition regexp $~") { "abc".partition(/b/); $~[0] }
