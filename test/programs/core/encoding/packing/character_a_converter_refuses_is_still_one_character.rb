# Ruby answers two questions about a multibyte String from two tables, and
# they disagree. Where a character ends comes from the encoding itself
# (onigmo's mbclen), so CP51932 reads 8F A1 A1 as ONE character and calls
# the String valid. What a character converts to comes from the
# transcoder, and CP51932's has no 8F form at all: the conversion refuses
# the 8F alone, and names that one byte. stateless-ISO-2022-JP does the
# same the other way round, with a two-byte character its own converter
# will not read.
[["CP51932", "\x8F\xA1\xA1"], ["stateless-ISO-2022-JP", "\x81\xA0"]].each do |name, bytes|
  text = bytes.dup.force_encoding(name)
  p [name, text.length, text.valid_encoding?, text.bytes.size]
  begin
    text.encode("UTF-8")
  rescue Encoding::InvalidByteSequenceError => e
    puts "#{e.class}: #{e.message}"
    p [e.error_bytes, e.readagain_bytes, e.incomplete_input?]
  end
end
# A character the encoding holds and gives no code point is the other
# failure, and it names the character, not the bytes.
begin
  "\x8F\xA1\xA1".dup.force_encoding("EUC-JP").encode("UTF-8")
rescue Encoding::UndefinedConversionError => e
  puts "#{e.class}: #{e.message}"
  p [e.error_char.bytes, e.source_encoding_name, e.destination_encoding_name]
end

