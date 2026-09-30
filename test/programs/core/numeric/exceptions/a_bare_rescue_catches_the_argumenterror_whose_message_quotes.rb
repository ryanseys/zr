# Integer(s) raises ArgumentError on unparseable input, as in CRuby.
# So `Integer(s) rescue 0` gives 0 for invalid input.
#
# The rescue fallbacks are Integers, the same type as the main
# value. With `rescue ArgumentError => e`, the test uses `puts e`.

# Bare rescue catches and lets us see the error message.
# The message must stay alive until the rescue body reads it.
begin
  Integer("nope")
rescue ArgumentError => err
  puts "msg: #{err}"
end

