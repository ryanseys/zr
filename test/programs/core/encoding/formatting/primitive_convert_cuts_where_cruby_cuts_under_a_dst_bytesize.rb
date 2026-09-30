# A converter's `#primitive_convert` cuts at CRuby's own point under a
# `dst_bytesize` limit. (This first line avoids naming the class outright:
# ruby would read `coding:` inside it as a magic comment.)
#
# A character whose output does not fit is still consumed from the source.
# The converter holds the output past the limit and drains it ahead of the
# next conversion. So the INTERMEDIATE state agrees with CRuby, not just the
# end state.
#
# Both rows below are pinned: where the cut falls, and what a drain answers.

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "#{label}: #{e.class}: #{e.message}"
end

show("cut point") do
  c = Encoding::Converter.new("UTF-8", "EUC-JP")
  src = +"あいう"
  dst = +""
  [c.primitive_convert(src, dst, 0, 2), src.bytes, dst.bytes]
end

# Draining reaches the same place: all six bytes, in order.
show("drained") do
  c = Encoding::Converter.new("UTF-8", "EUC-JP")
  src = +"あいう"
  dst = +""
  c.primitive_convert(src, dst, 0, 2)
  [c.primitive_convert(src, dst, dst.bytesize, 10), src.bytes, dst.bytes]
end
