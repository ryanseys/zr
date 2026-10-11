# ruby holds that a transcoded String is never broken (str_encode_associate
# scans it as ASCII-8BIT), so the result of an encode is valid even where
# the target's own reading of its bytes is not: "é" in Big5-HKSCS is
# 88 6D, and a lead byte under 0xA1 makes no Big5 character.
%w[Big5-HKSCS Big5-UAO CP951 Big5 EUC-JP Shift_JIS].each do |name|
  text = "aé日"
  out = begin
    text.encode(name)
  rescue EncodingError => e
    p [name, e.class]
    next
  end
  again = out.dup.force_encoding(name)
  p [name, out.bytes.map { _1.to_s(16) }, out.valid_encoding?, again.valid_encoding?, out.encode("UTF-8") == text]
end
# The same encoding, or an ASCII-only text, is not transcoded: it keeps
# what a scan says.
broken = "\x88\x6d".dup.force_encoding("Big5-HKSCS")
p broken.encode("Big5-HKSCS").valid_encoding?
p "abc".encode("Big5-HKSCS").valid_encoding?, "abc".encode("Big5-HKSCS").ascii_only?
p "é".encode("UTF-16LE").valid_encoding?
