# pack, unpack and unpack1 read the template as ASCII, so a template in
# an ASCII-incompatible encoding (UTF-16, UTF-32) raises
# Encoding::CompatibilityError. ASCII-compatible ones pack as usual.
[["C", "UTF-16LE"], ["u", "UTF-32BE"], ["C", "UTF-8"], ["C", "US-ASCII"], ["C", "BINARY"]].each do |fmt, enc|
  f = fmt.encode(enc)
  [-> { ["foo"].pack(f) rescue [0].pack(f) }, -> { "a".unpack(f) }, -> { "a".unpack1(f) }, -> { [0].pack(f, buffer: +"") }].each do |l|
    p l.call
  rescue => e
    p [e.class, e.message]
  end
end
