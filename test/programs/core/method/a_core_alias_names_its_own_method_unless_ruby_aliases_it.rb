# A core alias is a method that CRuby defines apart with the same C
# function, so its frame shows its own name ('Array#detect'). An alias
# that CRuby makes with rb_define_alias, or writes in its Ruby files,
# is its original, and the frame shows that name ('Array#push' for
# append, 'Time.local' for mktime).
require "pathname"

def l(tag)
  yield
rescue => e
  p [tag, e.backtrace_locations.first.label]
end

def m(tag)
  yield
  puts "#{tag}: ok"
rescue Exception => e
  puts "#{tag}: #{e.class} #{e.backtrace_locations&.first&.label}"
end
l(1) { [].freeze.append(1) }
l(2) { [1].detect(1, 2) {} }
l(3) { [1].collect(1) }
l(4) { Set[1].freeze << 2 }
l(5) { [].freeze.prepend(1) }
l(6) { {}.freeze.store(1, 2) }
l(7) { 1.magnitude(2) }
l(8) { "a".freeze.dedup(1) }
l(9) { :a.id2name(1) }
l(10) { [].freeze.collect! {} }
l(11) { [1].find_index(1, 2) }
l(12) { (1..2).each_entry(1) {} rescue raise }
l(13) { { a: 1 }.each_pair(1) }
l(14) { [1].map { raise "x" } }
l(15) { [1].collect { raise "x" } }
l(16) { (1..3).detect { raise "x" } }
l(17) { { a: 1 }.has_key?(1, 2) }
l(18) { "abc".slice(1, 2, 3) }
l(19) { [].freeze.filter! {} }
l(20) { 1.inspect(2) }
l(21) { 1.to_s(99) }
l(22) { "a".to_str(1) }
l(23) { :a.intern(1) }
l(24) { [3].size(1) }
l(25) { [3].length(1) }
l(26) { File.empty?(1) }
l(27) { 2.5.magnitude(1) }
l(28) { 2.then(1) }
l(29) { 2.yield_self(1) }
l(30) { Set[1].union(1) }
l(31) { 1.next(1) }
l(32) { 1.succ(1) }
l(33) { Kernel.format }
l(34) { Kernel.sprintf }
l(35) { [1].each_with_object }
m("Array#detect") { ([1, 2]).__send__(:detect, *Array.new(9, 0)) }
m("Complex.rect") { Complex.public_send(:rect, *Array.new(9, 0)) }
m("Complex#imag") { (Complex(1, 2)).__send__(:imag, *Array.new(9, 0)) }
m("Complex#rect") { (Complex(1, 2)).__send__(:rect, *Array.new(9, 0)) }
m("Complex#magnitude") { (Complex(1, 2)).__send__(:magnitude, *Array.new(9, 0)) }
m("Complex#angle") { (Complex(1, 2)).__send__(:angle, *Array.new(9, 0)) }
m("Complex#phase") { (Complex(1, 2)).__send__(:phase, *Array.new(9, 0)) }
m("Complex#conj") { (Complex(1, 2)).__send__(:conj, *Array.new(9, 0)) }
m("Complex#quo") { (Complex(1, 2)).__send__(:quo, *Array.new(9, 0)) }
m("Numeric#imag") { (1r).__send__(:imag, *Array.new(9, 0)) }
m("Numeric#rect") { (1r).__send__(:rect, *Array.new(9, 0)) }
m("Numeric#conj") { (1r).__send__(:conj, *Array.new(9, 0)) }
m("Numeric#angle") { (1r).__send__(:angle, *Array.new(9, 0)) }
m("Numeric#phase") { (1r).__send__(:phase, *Array.new(9, 0)) }
m("Float#angle") { (1.5).__send__(:angle, *Array.new(9, 0)) }
m("Float#phase") { (1.5).__send__(:phase, *Array.new(9, 0)) }
m("Data#to_s") { (Data.define(:a).new(a: 1)).__send__(:to_s, *Array.new(9, 0)) }
m("Enumerable#filter") { ((1..3).each_entry).__send__(:filter, *Array.new(9, 0)) }
m("Enumerable#find_all") { ((1..3).each_entry).__send__(:find_all, *Array.new(9, 0)) }
m("Enumerable#detect") { ((1..3).each_entry).__send__(:detect, *Array.new(9, 0)) }
m("Enumerable#member?") { ((1..3).each_entry).__send__(:member?, *Array.new(9, 0)) }
m("Float#to_int") { (1.5).__send__(:to_int, *Array.new(9, 0)) }
m("Hash#filter") { ({ a: 1 }).__send__(:filter, *Array.new(9, 0)) }
m("Hash#filter!") { ({ a: 1 }).__send__(:filter!, *Array.new(9, 0)) }
m("Hash#update") { ({ a: 1 }).__send__(:update, *Array.new(9, 0)) }
m("Hash#has_value?") { ({ a: 1 }).__send__(:has_value?, *Array.new(9, 0)) }
m("Integer#inspect") { (5).__send__(:inspect, *Array.new(9, 0)) }
m("Integer#===") { (5).__send__(:===, *Array.new(9, 0)) }
m("Integer#to_int") { (5).__send__(:to_int, *Array.new(9, 0)) }
m("Integer#truncate") { (5).__send__(:truncate, *Array.new(9, 0)) }
m("Integer#magnitude") { (5).__send__(:magnitude, *Array.new(9, 0)) }
m("Numeric#%") { (1r).__send__(:%, *Array.new(9, 0)) }
m("Kernel#yield_self") { (Object.new).__send__(:yield_self, *Array.new(9, 0)) }
m("Marshal.restore") { Marshal.public_send(:restore, *Array.new(9, 0)) }
m("Pathname#===") { (Pathname.new("a")).__send__(:===, *Array.new(9, 0)) }
m("Pathname#eql?") { (Pathname.new("a")).__send__(:eql?, *Array.new(9, 0)) }
m("Pathname#to_path") { (Pathname.new("a")).__send__(:to_path, *Array.new(9, 0)) }
m("Pathname#/") { (Pathname.new("a")).__send__(:/, *Array.new(9, 0)) }
m("Proc#===") { (proc {}).__send__(:===, *Array.new(9, 0)) }
m("Range#entries") { ((1..3)).__send__(:entries, *Array.new(9, 0)) }
m("Range#member?") { ((1..3)).__send__(:member?, *Array.new(9, 0)) }
m("Rational#magnitude") { (1r).__send__(:magnitude, *Array.new(9, 0)) }
m("Rational#quo") { (1r).__send__(:quo, *Array.new(9, 0)) }
m("Regexp#eql?") { (/a/).__send__(:eql?, *Array.new(9, 0)) }
m("MatchData#length") { ("ab".match(/a/)).__send__(:length, *Array.new(9, 0)) }
m("MatchData#deconstruct") { ("ab".match(/a/)).__send__(:deconstruct, *Array.new(9, 0)) }
m("MatchData#eql?") { ("ab".match(/a/)).__send__(:eql?, *Array.new(9, 0)) }
m("Set#intersection") { (Set[1]).__send__(:intersection, *Array.new(9, 0)) }
m("Set#difference") { (Set[1]).__send__(:difference, *Array.new(9, 0)) }
m("Set#+") { (Set[1]).__send__(:+, *Array.new(9, 0)) }
m("Set#union") { (Set[1]).__send__(:union, *Array.new(9, 0)) }
m("Set#eql?") { (Set[1]).__send__(:eql?, *Array.new(9, 0)) }
m("Set#<<") { (Set[1]).__send__(:<<, *Array.new(9, 0)) }
m("Set#map!") { (Set[1]).__send__(:map!, *Array.new(9, 0)) }
m("Set#member?") { (Set[1]).__send__(:member?, *Array.new(9, 0)) }
m("Set#===") { (Set[1]).__send__(:===, *Array.new(9, 0)) }
m("Set#to_s") { (Set[1]).__send__(:to_s, *Array.new(9, 0)) }
m("Set#<") { (Set[1]).__send__(:<, *Array.new(9, 0)) }
m("Set#>") { (Set[1]).__send__(:>, *Array.new(9, 0)) }
m("Set#length") { (Set[1]).__send__(:length, *Array.new(9, 0)) }
m("Set#filter!") { (Set[1]).__send__(:filter!, *Array.new(9, 0)) }
m("Set#<=") { (Set[1]).__send__(:<=, *Array.new(9, 0)) }
m("Set#>=") { (Set[1]).__send__(:>=, *Array.new(9, 0)) }
m("String#slice") { (+"abc").__send__(:slice, *Array.new(9, 0)) }
m("String#next") { (+"abc").__send__(:next, *Array.new(9, 0)) }
m("String#next!") { (+"abc").__send__(:next!, *Array.new(9, 0)) }
m("String#dedup") { (+"abc").__send__(:dedup, *Array.new(9, 0)) }
m("Symbol#size") { (:abc).__send__(:size, *Array.new(9, 0)) }
m("Symbol#next") { (:abc).__send__(:next, *Array.new(9, 0)) }
m("Symbol#id2name") { (:abc).__send__(:id2name, *Array.new(9, 0)) }
m("Struct#length") { (Struct.new(:a).new(1)).__send__(:length, *Array.new(9, 0)) }
m("Struct#filter") { (Struct.new(:a).new(1)).__send__(:filter, *Array.new(9, 0)) }
m("Struct#to_s") { (Struct.new(:a).new(1)).__send__(:to_s, *Array.new(9, 0)) }
m("Thread::Queue#<<") { (Thread::Queue.new).__send__(:<<, *Array.new(9, 0)) }
m("Thread::Queue#enq") { (Thread::Queue.new).__send__(:enq, *Array.new(9, 0)) }
m("Thread::Queue#length") { (Thread::Queue.new).__send__(:length, *Array.new(9, 0)) }
m("Time.gm") { Time.public_send(:gm, *Array.new(9, 0)) }
m("Time.mktime") { Time.public_send(:mktime, *Array.new(9, 0)) }
m("Time#mon") { (Time.at(0).utc).__send__(:mon, *Array.new(9, 0)) }
m("Time#mday") { (Time.at(0).utc).__send__(:mday, *Array.new(9, 0)) }
m("Time#tv_usec") { (Time.at(0).utc).__send__(:tv_usec, *Array.new(9, 0)) }
m("Time#tv_nsec") { (Time.at(0).utc).__send__(:tv_nsec, *Array.new(9, 0)) }
m("Time#tv_sec") { (Time.at(0).utc).__send__(:tv_sec, *Array.new(9, 0)) }
m("Time#gmt?") { (Time.at(0).utc).__send__(:gmt?, *Array.new(9, 0)) }
m("Time#gmt_offset") { (Time.at(0).utc).__send__(:gmt_offset, *Array.new(9, 0)) }
m("Time#gmtoff") { (Time.at(0).utc).__send__(:gmtoff, *Array.new(9, 0)) }
m("Time#isdst") { (Time.at(0).utc).__send__(:isdst, *Array.new(9, 0)) }
m("Time#gmtime") { (Time.at(0).utc).__send__(:gmtime, *Array.new(9, 0)) }
m("Time#getgm") { (Time.at(0).utc).__send__(:getgm, *Array.new(9, 0)) }
m("Time#asctime") { (Time.at(0).utc).__send__(:asctime, *Array.new(9, 0)) }
m("Time#xmlschema") { (Time.at(0).utc).__send__(:xmlschema, *Array.new(9, 0)) }
m("Time.local 0") { Time.local }
m("Time.utc 9") { Time.utc(1, 2, 3, 4, 5, 6, 7, 8, 9) }
m("Time.mktime 9") { Time.mktime(1, 2, 3, 4, 5, 6, 7, 8, 9) }
m("Time.gm 10") { p Time.gm(0, 0, 0, 1, 1, 2000, nil, nil, false, nil).year }
