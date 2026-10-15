# ENV.assoc gives the name it was asked with and a frozen value;
# ENV.rassoc gives a new, unfrozen name and the value it was asked with;
# ENV.key compares any String's bytes, a NUL too, and gives a frozen name.
name = +"ZR_ENV_PAIRS_TEST"
value = +"pair value"
ENV[name] = value

pair = ENV.assoc(name)
p pair, pair[0].equal?(name), pair.map(&:frozen?)
reverse = ENV.rassoc(value)
p reverse, reverse[1].equal?(value), reverse.map(&:frozen?)
p ENV.rassoc(value)[0].equal?(ENV.rassoc(value)[0])
p ENV.key(value), ENV.key(value).frozen?
p name.frozen?, value.frozen?

class Named
  def to_str = "ZR_ENV_PAIRS_TEST"
end
p ENV.assoc(Named.new)
p ENV.rassoc(Named.new), ENV.key(Named.new)

def try(label)
  p [label, yield]
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

try("key with a NUL") { ENV.key("pair\0value") }
try("key of an Integer") { ENV.key(1) }
try("rassoc with a NUL") { ENV.rassoc("pair\0value") }
try("rassoc of an Integer") { ENV.rassoc(1) }
try("assoc with a NUL") { ENV.assoc("ZR\0NAME") }
try("assoc of an Integer") { ENV.assoc(1) }
try("assoc of a missing name") { ENV.assoc("ZR_ENV_PAIRS_MISSING") }
try("key of a missing value") { ENV.key("no such value anywhere") }

ENV.delete(name)
p ENV.assoc(name), ENV.rassoc(value)
