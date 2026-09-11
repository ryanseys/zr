# An inspect that answers something other than a String is made one by
# rb_obj_as_string's rule: its to_s, else the #<Class:0x...> form. So is
# a to_s that answers no String, where puts or interpolation needs one.
def hide(s) = s.gsub(/0x\h+/, "0xXX")

num = Object.new
def num.inspect = 42
nothing = Object.new
def nothing.inspect = nil
odd = Object.new
def odd.inspect = Object.new

p [num]
p({num => num})
puts [nothing].inspect
puts hide([odd].inspect)
holder = Object.new
holder.instance_variable_set(:@x, num)
puts hide(holder.inspect)
begin
  {a: 1}.fetch(num)
rescue KeyError => e
  puts e.message
end

bad = Object.new
def bad.to_s = 7
puts hide("#{bad}")
puts hide(bad.to_s.to_s)
$stdout.puts hide([bad].join(",")) rescue puts "join: #{$!.class}"
__END__
[42]
{42 => 42}
[]
[#<Object:0xXX>]
#<Object:0xXX @x=42>
key not found: 42
#<Object:0xXX>
7
#<Object:0xXX>
