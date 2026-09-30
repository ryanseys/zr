# Integer(s) raises ArgumentError on unparseable input, as in CRuby.
# So `Integer(s) rescue 0` gives 0 for invalid input.
#
# The rescue fallbacks are Integers, the same type as the main
# value. With `rescue ArgumentError => e`, the test uses `puts e`.

# Many raises in succession cause many allocations. Each
# `Integer("bad...")` makes a new message. A collection between
# the raise and the rescue must keep the message alive until the
# rescue body ends.
i = 0
ok = 0
while i < 100
  caught = 0
  begin
    Integer("bad")
  rescue ArgumentError
    caught = 1
  end
  ok += caught
  i += 1
end
puts "stress ok: #{ok}"

