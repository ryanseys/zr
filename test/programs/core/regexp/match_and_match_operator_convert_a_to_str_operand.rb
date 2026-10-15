# Regexp#match, =~ and === take a Symbol's name or what to_str gives;
# anything else raises TypeError, as reg_operand does.
class Needle
  def to_str = "a needle here"
end

class Broken
  def to_str = 1
end

def try
  p yield
rescue => e
  puts "#{e.class}: #{e.message}"
end

needle = Needle.new
try { /needle/.match(needle) }
try { /needle/.match(needle).string.frozen? }
try { /needle/.match(needle).pre_match }
try { /needle/.match(needle, 3) }
try { /needle/.match(needle, -6) }
try { /needle/ =~ needle }
try { $~ }
try { /needle/ === needle }
try { /needle/.match?(needle) }
try { /needle/.match(needle) { |m| m.post_match } }
try { /x/ =~ needle }
try { $~ }
try { /needle/.match(:"a needle") }
try { /needle/ =~ :needle }
try { /a/.match(1) }
try { /a/ =~ Object.new }
try { /a/.match(Broken.new) }
try { /a/ === 1 }
try { /a/.match(nil) }
try { /a/ =~ nil }
