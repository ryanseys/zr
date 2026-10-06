# Regex coverage — five stages plus literal-form tests. Each section
# gives its locals names of its own (`re_s1a`, ...).


re_ml1 = /
  bar
/x
if re_ml1 =~ "barbar"
  puts "ok1"
else
  puts "no1"
end

re_ml_t = /a\tb/
if re_ml_t =~ "a\tb"
  puts "ok2"
else
  puts "no2"
end

re_ml_n = /a\nb/
if re_ml_n =~ "a\nb"
  puts "ok3"
else
  puts "no3"
end

re_ml_r = /a\rb/
if re_ml_r =~ "a\rb"
  puts "ok4"
else
  puts "no4"
end

# InterpolatedRegularExpressionNode (/foo_#{x}/). The pattern is only known
# at execution time. =~, match?, match, gsub, sub, scan, and split all
# accept either form.

# match? predicate (boolean).
ir_x = "bar"
puts "foo_bar".match?(/foo_#{ir_x}/)   #=> true
puts "foo_baz".match?(/foo_#{ir_x}/)   #=> false

# Captures populate $1
if "foo_bar_42" =~ /foo_#{ir_x}_(\d+)/
  puts $1   #=> 42
end

# gsub with interpolated pattern
ir_who = "world"
puts "hello world".gsub(/#{ir_who}/, "Ruby")   #=> hello Ruby

# sub
puts "abc 123 def".sub(/(\d+)/, "X")           #=> abc X def

# Interpolation that varies per-iteration (proves no stale cache and
# that runtime compilation actually re-fires per evaluation).
ir_i = 0
while ir_i < 3
  ir_seed = ir_i.to_s
  puts ("v_" + ir_seed).match?(/v_#{ir_seed}/)
  ir_i = ir_i + 1
end
#=> true
#=> true
#=> true
