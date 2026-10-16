# CRuby caches a String's coderange: a String joined from pieces that are
# each valid is valid, with no scan of the joined bytes. ruby's Big5-HKSCS
# transcoder writes "é" as 88 6D, which its own byte table splits into
# two characters, so the scan would find 88 invalid. zr scans the bytes.
s = +""
s << "A".encode("Big5-HKSCS") << "é".encode("Big5-HKSCS") << "中".encode("Big5-HKSCS")
p s.encoding, s.valid_encoding?
p s.chars.map(&:valid_encoding?)
p s.dup.force_encoding("Big5-HKSCS").valid_encoding?
p s.b.force_encoding("Big5-HKSCS").valid_encoding?
