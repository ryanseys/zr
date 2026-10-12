# scrub! refuses a block with a replacement before it looks at the text.
# chomp! of an empty String is nil before the separator converts.
# byteindex and byterindex check the offset before the needle converts.
# append_as_bytes and Range#overlap? name the class of a bad argument.
def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

show("scrub! both") { (+"a").scrub!("?") { "x" } }
show("scrub! both, invalid") { (+"a\xff").scrub!("?") { "x" } }
show("scrub! both, frozen") { "a".freeze.scrub!("?") { "x" } }
show("scrub! nil and block") { (+"a\xff").scrub!(nil) { "z" } }
show("scrub! block") { (+"a\xff").scrub! { |b| "<#{b.bytes}>" } }
show("scrub! valid, frozen") { "a".freeze.scrub! }
show("scrub both") { "a".scrub("?") { "x" } }

show("chomp! empty") { [(+"").chomp!(1), (+"").chomp!(nil), (+"").chomp!, (+"").chomp!(:a)] }
show("chomp! empty, frozen") { "".freeze.chomp!(1) }
show("chomp! bad separator") { (+"a").chomp!(1) }
show("chomp!") { [(+"ab\n").chomp!, (+"ab").chomp!("b"), (+"ab").chomp!(nil), (+"a").chomp!("z"), (+"a\r\n").chomp!("")] }

show("byteindex") { ["".byteindex(2, 1), "abc".byteindex(2, 9), "abc".byteindex(:a, -9), "é😀".byteindex("😀", 2), "abc".byteindex("c"), "abc".byteindex(/c/, 4)] }
show("byteindex off a boundary") { "é😀".byteindex(2, 1) }
show("byteindex bad needle") { "abc".byteindex(2, 1) }
show("byteindex bad offset") { "abc".byteindex("a", "1") }
show("byterindex") { ["".byterindex(2, -1), "é😀".byterindex("é", 0), "abcb".byterindex("b"), "abc".byterindex(/a/, -9)] }
show("byterindex off a boundary") { "é😀".byterindex(2, 1) }
show("byterindex bad needle") { "abc".byterindex(2) }

[nil, true, 1.5, :a, Object.new.freeze, [1]].each do |x|
  show("append_as_bytes #{x.class}") { (+"").append_as_bytes(x) }
  show("overlap? #{x.class}") { (1..2).overlap?(x) }
end
