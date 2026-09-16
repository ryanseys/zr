# The stream fields ruby exposes: data_type as deflate guesses it, the
# adler, the totals, the buffers' counts, and the finished flags.
require "zlib"

def fields(z) = "type #{z.data_type} adler #{z.adler} in #{z.total_in} out #{z.total_out} avail_in #{z.avail_in} avail_out #{z.avail_out} finished #{z.finished?}"

d = Zlib::Deflate.new(6)
puts "new: #{fields(d)}"
d << "plain text is text, plain text is text\n"
puts "text: #{fields(d)}"
d.finish
puts "finished: #{fields(d)}"
d.close

d = Zlib::Deflate.new(6)
d.deflate((0..255).to_a.pack("C*") * 4, Zlib::FINISH)
puts "binary: #{fields(d)}"
d.close

d = Zlib::Deflate.new(6)
d.deflate("tabs\tand\nnewlines\rare text; \x1b is not", Zlib::FINISH)
puts "escape: #{fields(d)}"
d.close

d = Zlib::Deflate.new(6)
d.deflate("\x00\x01\x02 low bytes", Zlib::FINISH)
puts "low bytes: #{fields(d)}"
d.close

d = Zlib::Deflate.new(0)
d.deflate("stored, so the type is not detected", Zlib::FINISH)
puts "level 0: #{fields(d)}"
d.close

d = Zlib::Deflate.new(6)
d.deflate("", Zlib::FINISH)
puts "empty: #{fields(d)}"
d.close

d = Zlib::Deflate.new(6, 31)
d.deflate("gzip carries a crc32", Zlib::FINISH)
puts "gzip: #{fields(d)} = crc #{Zlib.crc32("gzip carries a crc32")}"
d.close

d = Zlib::Deflate.new(6, -15)
d.deflate("raw keeps an adler anyway", Zlib::FINISH)
puts "raw: #{fields(d)}"
d.close

packed = Zlib::Deflate.deflate("inflate side totals and adler", 6)
i = Zlib::Inflate.new
puts "new: #{fields(i)}"
i.inflate(packed[0, 5])
puts "partial: #{fields(i)}"
i.inflate(packed[5..])
puts "whole: #{fields(i)}"
puts "stream end: #{i.stream_end?} closed #{i.closed?}"
i.close
puts "closed: #{i.closed?}"

i = Zlib::Inflate.new
i.inflate(packed + "trailing bytes")
puts "trailing: #{fields(i)} rest #{i.flush_next_in.inspect}"
i.close

__END__
new: type 2 adler 1 in 0 out 0 avail_in 0 avail_out 0 finished false
text: type 2 adler 522456587 in 39 out 2 avail_in 0 avail_out 1022 finished false
finished: type 1 adler 522456587 in 39 out 28 avail_in 0 avail_out 0 finished true
binary: type 0 adler 3838443024 in 1024 out 286 avail_in 0 avail_out 0 finished true
escape: type 1 adler 3927379043 in 36 out 44 avail_in 0 avail_out 0 finished true
low bytes: type 0 adler 320537533 in 13 out 21 avail_in 0 avail_out 0 finished true
level 0: type 2 adler 3846114514 in 35 out 46 avail_in 0 avail_out 0 finished true
empty: type 0 adler 1 in 0 out 8 avail_in 0 avail_out 0 finished true
gzip: type 1 adler 2544769400 in 20 out 40 avail_in 0 avail_out 0 finished true = crc 2544769400
raw: type 1 adler 1 in 25 out 25 avail_in 0 avail_out 0 finished true
new: type 0 adler 1 in 0 out 0 avail_in 0 avail_out 0 finished false
partial: type 69 adler 21102808 in 5 out 2 avail_in 0 avail_out 0 finished false
whole: type 64 adler 2764704475 in 37 out 29 avail_in 0 avail_out 0 finished true
stream end: true closed false
closed: true
trailing: type 64 adler 2764704475 in 37 out 29 avail_in 0 avail_out 0 finished true rest ""
