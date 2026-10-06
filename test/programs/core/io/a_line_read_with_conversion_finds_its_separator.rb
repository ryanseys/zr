# With a read conversion to an encoding that is not ASCII compatible, a
# line still ends at its separator: the stream looks for it in the bytes
# before the conversion.
IO.pipe do |r, w|
  [Encoding::UTF_32BE, Encoding::UTF_16LE, Encoding::UTF_8].each do |e|
    r.set_encoding(Encoding::US_ASCII, e)
    w.print("one\n\n\n\ntwo\nthree|four\n")
    p r.gets(""), r.gets, r.gets("|".encode(e))
    p r.gets.encoding
  end
end
