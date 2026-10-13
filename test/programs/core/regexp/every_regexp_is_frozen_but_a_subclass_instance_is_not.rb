# ruby 4.1 freezes every instance of Regexp itself, however it is made:
# a literal, Regexp.new, Regexp.compile, Regexp.union, dup, clone and
# Marshal.load. An instance of a subclass is not frozen.
x = "b"
made = {
  literal: /abc/,
  interpolated: /a#{x}c/,
  new: Regexp.new("abc"),
  new_from_regexp: Regexp.new(/abc/i),
  compile: Regexp.compile("a+", Regexp::IGNORECASE),
  union: Regexp.union("a", /b/),
  union_of_one: Regexp.union("a.b"),
  escape_then_new: Regexp.new(Regexp.escape("a.b")),
  dup: Regexp.new("abc").dup,
  clone: Regexp.new("abc").clone,
  clone_unfrozen: Regexp.new("abc").clone(freeze: false),
  marshal: Marshal.load(Marshal.dump(/abc/m)),
  allocate_then_initialize: Regexp.allocate.tap { |re| re.send(:initialize, "abc") }
}
made.each { |how, re| puts "#{how}: #{re.frozen?} #{re.inspect}" }

class Pattern < Regexp; end
sub = Pattern.new("abc")
puts "subclass: #{sub.frozen?} #{sub.class}"
puts "subclass dup: #{sub.dup.frozen?}"
puts "subclass marshal: #{Marshal.load(Marshal.dump(sub)).frozen?}"

# A frozen Regexp refuses initialize again, before the
# "already initialized" check.
[Regexp.new("abc"), /lit/].each do |re|
  re.send(:initialize, "x")
rescue => e
  puts "#{e.class}: #{e.message}"
end
begin
  sub.send(:initialize, "x")
rescue => e
  puts "#{e.class}: #{e.message}"
end

# A frozen Regexp refuses an instance variable and a singleton method.
re = Regexp.new("abc")
[-> { re.instance_variable_set(:@a, 1) }, -> { def re.extra = 1 }, -> { re.extend(Comparable) }].each do |change|
  change.call
rescue => e
  puts "#{e.class}: #{e.message}"
end
sub.instance_variable_set(:@a, 1)
p sub.instance_variable_get(:@a)

# Matching still works on every frozen Regexp, and sets $~.
p made[:new].match?("xabcx"), made[:union] =~ "zb", $~[0]
