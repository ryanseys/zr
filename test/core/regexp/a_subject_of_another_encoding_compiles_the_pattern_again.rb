# A pattern that fixed no encoding reads a subject of another encoding
# by compiling its source again under the subject's (rb_reg_prepare_re):
# the escapes decode as that encoding's characters, a byte no character
# of it holds is refused at the match, and the compile stays the
# pattern's until a subject of yet another encoding asks.

def try(re, subject)
  m = re.match(subject)
  m ? [m[0].bytes, m.begin(0)] : nil
rescue ArgumentError, Encoding::CompatibilityError => e
  [e.class, e.message]
end

loose = Regexp.new('\A[\xff]'.dup.force_encoding("US-ASCII"))
p [loose.encoding, loose.fixed_encoding?]
p try(loose, "abc")
p try(loose, "\xff".b)
p try(loose, "é")
p try(loose, "abc")

# A comment's high byte is nothing to US-ASCII, and not a character of
# UTF-8 once a subject compiles the pattern under it.
latin = Regexp.new("(?#\xE9)b".dup.force_encoding("ISO-8859-1"))
p [latin.encoding, latin.source.bytes]
p try(latin, "ab")
p try(latin, "\xE9b".dup.force_encoding("ISO-8859-1"))
p try(latin, "ab")
p try(latin, "éb")

# `\xE3\x81\x82` is one character under UTF-8 and three bytes under BINARY.
octets = Regexp.new('\xE3\x81\x82.', Regexp::NOENCODING)
p [octets.encoding, octets.options]
p try(octets, "\xE3\x81\x82\x80".b)
$stderr.puts "--"
p try(octets, "あい")
p try(/./n, "あ")

# A fixed pattern refuses a subject past ASCII in another encoding.
fixed = /é./
p try(fixed, "éa".encode("ISO-8859-1"))
p try(fixed, "ab".encode("UTF-16LE"))
p try(fixed, "ab".b)

__END__
[#<Encoding:US-ASCII>, false]
nil
[[255], 0]
[ArgumentError, "regexp preprocess failed: invalid multibyte escape"]
[ArgumentError, "regexp preprocess failed: invalid multibyte escape"]
[#<Encoding:US-ASCII>, [40, 63, 35, 233, 41, 98]]
[[98], 1]
[[98], 1]
[ArgumentError, "regexp preprocess failed: invalid multibyte character"]
[ArgumentError, "regexp preprocess failed: invalid multibyte character"]
[#<Encoding:BINARY (ASCII-8BIT)>, 48]
[[227, 129, 130, 128], 0]
[Encoding::CompatibilityError, "incompatible encoding regexp match (BINARY (ASCII-8BIT) regexp with UTF-8 string)"]
[[227, 129, 130], 0]
[Encoding::CompatibilityError, "incompatible encoding regexp match (UTF-8 regexp with ISO-8859-1 string)"]
[Encoding::CompatibilityError, "incompatible encoding regexp match (UTF-8 regexp with UTF-16LE string)"]
nil
#@ stderr
--
core/regexp/a_subject_of_another_encoding_compiles_the_pattern_again.rb:8: warning: historical binary regexp match /.../n against UTF-8 string
