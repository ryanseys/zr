# full_message starts in binary and detailed_message in US-ASCII, as
# CRuby's buffers do: text past ASCII gives them its encoding, and a
# message in an encoding that is not ASCII-compatible counts as empty.
[["\x00"], ["ok"], ["café"], ["\xff"], ["x".encode("UTF-16LE")], ["\x00".encode("US-ASCII")], ["a".b]].each do |(msg)|
  e = RuntimeError.new(msg)
  m = e.full_message(highlight: false)
  p [m.encoding, m.valid_encoding?, m.end_with?("(RuntimeError)\n"), e.message.encoding]
end
p RuntimeError.new("\x00").full_message(highlight: true).encoding
p RuntimeError.new("\x00").detailed_message.encoding
[["x\ny"], ["x\ny".encode("UTF-16LE")], ["é\n\nz"], [""], ["a\n"]].each do |(msg)|
  [RuntimeError, IOError, Class.new(StandardError)].each do |klass|
    [false, true].each do |hl|
      d = klass.new(msg).detailed_message(highlight: hl)
      p [d.encoding, d.sub(/#<Class:0x\h+>/, "anon")]
    end
  end
end
p RuntimeError.new("\x00").full_message(highlight: false).inspect.end_with?("\\x00 (RuntimeError)\\n\"")
