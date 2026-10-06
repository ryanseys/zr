# ObjectSpace.dump writes the fields of each type in the order of CRuby's
# dump_object. Addresses, sizes and GC flags differ by heap, so they are
# masked.
require "objspace"

def show(obj)
  line = ObjectSpace.dump(obj)
  line = line.gsub(/"0x\h+"/, '"ADDR"').sub(/, "references":\[[^\]]*\]/, "").sub(/, "memsize":\d+/, "")
  line = line.sub(/"shape_id":\d+/, '"shape_id":N').sub(/"slot_size":\d+/, '"slot_size":N').sub(/"variation_count":\d+/, '"variation_count":N').sub(/, "flags":\{.*\}/, "")
  puts line
end

show("abc".freeze)
show(+"x" * 100)
show("lit")
show("\xff")
show("a".b)
show("\xff".b)
show(-"z#{1}")
show(:abc.to_s)
show("é")
show("a".encode("UTF-16LE"))
show("")
show("a\e\"\\\x7f\n".freeze)
show([1, 2])
show({ a: 1 })
show(Hash.new {})
o = Object.new
o.instance_variable_set(:@a, 1)
show(o)
show(Object.new.singleton_class)
show(Comparable)
show(Module.new)
show(String)
show(1.5e300 * 10)
puts ObjectSpace.dump(:abc)
puts ObjectSpace.dump(nil), ObjectSpace.dump(1), ObjectSpace.dump(1.5)
p ObjectSpace.dump("a").encoding
s = "test_uplus_minus_str".freeze
p ObjectSpace.dump(s).include?('"fstring":true')
p ObjectSpace.dump("abc").include?('"fstring"')
a = "a" * 32
res = "#{a}, #{"a" * 128}"
p ObjectSpace.dump(res).include?('"embedded":true')
p Integer(ObjectSpace.dump(res)[/"slot_size":(\d+)/, 1]) > Integer(ObjectSpace.dump(a)[/"slot_size":(\d+)/, 1])
long = "b" * 1000
p ObjectSpace.dump(long).include?('"embedded"')
p ObjectSpace.dump(Hash.new { 1 }).include?('"references"')
def made_here = Object.new
traced = ObjectSpace.trace_object_allocations { made_here }
fields = ObjectSpace.dump(traced)
p fields[/"file":"[^"]*"/].end_with?(%(#{File.basename(__FILE__)}"))
p fields[/"line":\d+/] == %("line":#{__LINE__ - 4})
p fields[/"method":"\w+"/]
p fields.include?(%("generation":))
p ObjectSpace.dump("a\u3042".freeze).include?(%("coderange":"valid"))
p ObjectSpace.dump("\xE3".force_encoding("UTF-8")).include?(%("broken":true))
