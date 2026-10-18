# String#inspect writes printable text as it is, a run at a time, and
# escapes each character that ends a run: quotes, backslashes, a `#` that
# starts interpolation, control characters, characters outside Onigmo's
# Print class (unassigned, NEL, line separator), and bytes that make no
# character. A String in another encoding than inspect's shows each
# character past ASCII by its code point.
samples = [
  "plain words", "Straße ΣΊΣΥΦΟΣ", "a\"b\\c", "#{1}#x", "\#{x} \#$y \#@z #",
  "tab\there\nnl", "\u0085nel", " nbsp", " sep", "͸unassigned",
  "​zw", "﻿bom", "private", "\u{1F600} emoji", "\u{10FFFF}",
  "é\xffé", "\xe2\x82", "end͸", "͸", "", "x" * 40 + "͸" + "y" * 40,
  "ǅ\u{1E900}x Ⓐⓑ \u{10400}",
]
samples.each { |s| puts s.inspect }
samples.each { |s| puts s.dup.force_encoding("UTF8-MAC").inspect }
samples.each { |s| puts s.encode("UTF-16LE", invalid: :replace).inspect }
p samples.map { |s| s.inspect.encoding }.uniq
