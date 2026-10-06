# Which CLASS owns a builtin method is part of its behaviour, not a detail of
# reflection: it decides which receivers answer it. This locks the boundaries
# the arity census proved zr had drawn in the wrong place.

require "pathname"
require "tmpdir"

def owner_of(klass, name)
  klass.instance_method(name).owner
rescue NameError
  "absent"
end

# Names that CRuby does not define anywhere.
puts "-- not methods at all"
{
  "Regexp#linear_time?" => -> { /a/.linear_time? },
  "Set#contain?" => -> { require("set") || Set.new([1]).contain?(1) },
  "Set#merge_new" => -> { require("set") || Set.new([1]).merge_new([2]) },
  "Pathname#to_str" => -> { Pathname.new("/tmp").to_str },
  "Pathname#mkdir_p" => -> { Pathname.new("/tmp").mkdir_p },
  "Pathname#rm_rf" => -> { Pathname.new("/tmp").rm_rf },
  "Proc#()" => -> { ->(x) { x }.public_send(:"()", 1) },
  "Struct[]" => -> { Struct[:a] },
}.each do |label, probe|
  begin
    probe.call
    puts "#{label}: answered"
  rescue NoMethodError
    puts "#{label}: NoMethodError"
  end
end

