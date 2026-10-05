# Regexp#match? reads a Symbol's name and converts anything else with
# to_str, raising TypeError for an object that has none.
def t(l)
  p [l, yield]
rescue StandardError => e
  p [l, e.class, e.message]
end
t(1) { //.match?(nil) }
t(2) { //.match?("") }
t(3) { /.../.match?(:abc) }
t(4) { /.../.match?(Object.new) }
t(5) { /../.match?("abc", -2) }
t(6) { /../.match?("abc", -4) }
t(7) { /../.match?("abc", 4) }
t(8) { /../.match?("あxx", 1) }
t(9) { /../.match?("あx", 1) }
t(10) { /\z/.match?("") }
t(11) { /R.../.match?("Ruby", 1) }
t(12) { /a/.match?(Struct.new(:to_str).new("cat")) }
