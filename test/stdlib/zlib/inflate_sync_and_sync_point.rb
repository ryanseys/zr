# inflateSync finds the next full-flush point after damage, and
# sync_point? reports a stream stopped at one.
require "zlib"

d = Zlib::Deflate.new(6)
head = d.deflate("the part before the flush point, ", Zlib::FULL_FLUSH)
tail = d.deflate("and the part after it", Zlib::FINISH)
d.close
puts "head ends with the empty stored block: #{head[-4..].unpack1("H*")}"

i = Zlib::Inflate.new
puts "read: #{i.inflate(head[0, 6]).inspect}"
puts "sync point mid-block: #{i.sync_point?}"
puts "read: #{i.inflate(head[6..]).inspect}"
puts "sync point at the flush: #{i.sync_point?}"
puts "read: #{i.inflate(tail).inspect}"
puts "finished: #{i.finished?}"
i.close

garbage = "\xff\x00\x11\x22".b
i = Zlib::Inflate.new
out = +""
out << i.inflate(head[0, 4])
begin
  out << i.inflate(garbage + head[4..] + tail)
rescue Zlib::DataError => e
  puts "damage: #{e.message}"
end
puts "sync into the rest: #{i.sync(head[-4..] + tail)}"
puts "after sync: #{i.inflate("").inspect}"
puts "finished: #{i.finished?}"
i.close

i = Zlib::Inflate.new
i.inflate(head[0, 4])
puts "sync with no marker: #{i.sync("no marker in here at all")}"
puts "sync with a marker later: #{i.sync("xx\x00\x00\xff\xffdata".b)}"
i.close

i = Zlib::Inflate.new
puts "sync before any input: #{i.sync(head + tail)}"
i.close

d = Zlib::Deflate.new(6)
a = d.deflate("sync", Zlib::SYNC_FLUSH)
b = d.deflate("flush", Zlib::SYNC_FLUSH)
c = d.finish
d.close
i = Zlib::Inflate.new
[a, b, c].each do |piece|
  got = i.inflate(piece)
  puts "#{got.inspect} sync point #{i.sync_point?} finished #{i.finished?}"
end
i.close

__END__
head ends with the empty stored block: 0000ffff
read: "the"
sync point mid-block: false
read: " part before the flush point, "
sync point at the flush: false
read: "and the part after it"
finished: true
damage: invalid distance too far back
sync into the rest: true
after sync: "o\xF0and the part after it"
finished: true
sync with no marker: false
sync with a marker later: true
sync before any input: true
"sync" sync point false finished false
"flush" sync point false finished false
"" sync point false finished true
