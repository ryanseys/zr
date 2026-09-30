# A Regexp over text in a single-byte encoding reads each byte with that
# encoding's own tables: its word and POSIX classes, its lower-case
# table under /i, and a sharp s that folds to "ss" where the encoding
# says so. An encoding ruby replicates from ASCII-8BIT (IBM437,
# macRoman, ...) knows ASCII alone.
def re(source, enc, options = 0) = Regexp.new(source.encode(enc), options | Regexp::FIXEDENCODING)
def show(match) = match && [match.byteoffset(0), match[0].encode("UTF-8")]

latin = "Ünïcödé Straße".encode("ISO-8859-1")
p show(re("\\w+", "ISO-8859-1").match(latin)), latin.scan(re("[[:upper:]]", "ISO-8859-1")).size
p show(re("strasse", "ISO-8859-1", Regexp::IGNORECASE).match(latin)), show(re("ünï", "ISO-8859-1", Regexp::IGNORECASE).match(latin))
p show(re("ß", "ISO-8859-1", Regexp::IGNORECASE).match("STRASSE".encode("ISO-8859-1")))
p show(re("SS", "ISO-8859-15", Regexp::IGNORECASE).match("straße".encode("ISO-8859-15")))

greek = "Καλημέρα ΚΌΣΜΕ".encode("ISO-8859-7")
p show(re("κόσμε", "ISO-8859-7", Regexp::IGNORECASE).match(greek)), greek.scan(re("[[:lower:]]+", "ISO-8859-7")).map { _1.encode("UTF-8") }
p show(re("\\w+$", "Windows-1253").match("Γειά σου".encode("Windows-1253")))

cyrillic = "Привет МИР".encode("KOI8-R")
p show(re("мир", "KOI8-R", Regexp::IGNORECASE).match(cyrillic)), cyrillic.split(re("\\s", "KOI8-R")).map { _1.encode("UTF-8") }
p show(re("[а-я]+", "Windows-1251", Regexp::IGNORECASE).match("ПРИВЕТ".encode("Windows-1251")))
p show(re("ї", "KOI8-U", Regexp::IGNORECASE).match("Ї".encode("KOI8-U")))
p show(re("\\bмир\\b", "ISO-8859-5").match("привет мир!".encode("ISO-8859-5")))

p show(re("ı", "Windows-1254", Regexp::IGNORECASE).match("I".encode("Windows-1254"))), show(re("i", "ISO-8859-9", Regexp::IGNORECASE).match("İ".encode("ISO-8859-9")))
p show(re("ą+", "ISO-8859-2", Regexp::IGNORECASE).match("ĄĄą".encode("ISO-8859-2"))), show(re("ž", "Windows-1250", Regexp::IGNORECASE).match("Ž".encode("Windows-1250")))
p show(re("š", "Windows-1257", Regexp::IGNORECASE).match("Š".encode("Windows-1257"))), show(re("ŵ", "ISO-8859-14", Regexp::IGNORECASE).match("Ŵ".encode("ISO-8859-14")))
p show(re("\\w", "ISO-8859-6").match("ب".encode("ISO-8859-6"))), show(re("\\w", "ISO-8859-8").match("א".encode("ISO-8859-8")))
p show(re("[[:alpha:]]", "TIS-620").match("ก".encode("TIS-620"))), show(re("\\w", "Windows-1255").match("א".encode("Windows-1255")))

ibm = "\x80\x81ab".dup.force_encoding("IBM437")
p re("\\w+", "IBM437").match(ibm).byteoffset(0), re("[\\x80-\\xff]+".b.force_encoding("IBM437"), "IBM437").match(ibm)&.byteoffset(0)
p re("é", "macRoman", Regexp::IGNORECASE).match("É".encode("macRoman"))&.byteoffset(0)
p "abc\xFF".dup.force_encoding("US-ASCII").valid_encoding?, (/b/ =~ "ab".encode("US-ASCII"))
p (re("\\xe9".b, "ISO-8859-1") =~ "caf\xE9".dup.force_encoding("ISO-8859-1"))


