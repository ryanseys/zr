# The wide Unicode rows (UTF-16LE/BE, UTF-32LE/BE): NOT ASCII-compatible
# (never ascii_only, even empty; concatenation with anything else only
# through an empty side), surrogate-pair walking, scalar-based chr/<<,
# \uXXXX-escaped inspect. Verbatim ruby output.

u = "ab€".encode("UTF-16LE")
p u.bytes
p u.length
p u.valid_encoding?
p u
p u.encode("UTF-8")
p u.upcase.bytes
p "a€𝄞".encode("UTF-32BE").bytes
p "a€𝄞".encode("UTF-32BE").length
p "a€𝄞".encode("UTF-16BE").encode("UTF-32LE").encode("UTF-8")
p 65.chr(Encoding::UTF_16LE).bytes
s = "".encode("UTF-16LE"); s << 0x20AC; p s.bytes
p ("a".encode("UTF-16LE") + "").encoding
begin; "a".encode("UTF-16LE") + "b"; rescue Encoding::CompatibilityError => e; puts e.message; end
p ("".encode("UTF-16LE") + "abc").encoding
p "abc".dup.force_encoding("UTF-16LE").ascii_only?
p "a".dup.force_encoding("UTF-16LE").valid_encoding?
bad = (0xD8.chr + 0x34.chr).force_encoding("UTF-16BE")
p bad.valid_encoding?
begin; bad.encode("UTF-8"); rescue Encoding::InvalidByteSequenceError => e; puts e.message; end
p "AB𝄞".encode("UTF-16BE")
p Encoding::UTF_16LE.ascii_compatible?
p Encoding.find("UCS-2BE")
