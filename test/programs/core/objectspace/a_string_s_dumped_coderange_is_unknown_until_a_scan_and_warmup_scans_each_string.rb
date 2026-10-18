# A String keeps its coderange (7bit, valid, broken or unknown) as CRuby
# does: a literal has it from the compiler, a repeat takes it from its
# source, and a new encoding or a new String from other parts leaves it
# unknown until a scan. ObjectSpace.dump writes it with no scan of its
# own, and Process.warmup scans every String.
require "objspace"

def coderange(s) = ObjectSpace.dump(s)[/"coderange":"(\w+)"/, 1]

str = "a" * 12
p coderange(str)
str.force_encoding(Encoding::UTF_16LE)
str.force_encoding(Encoding::BINARY)
p coderange(str)
p ObjectSpace.dump(str).include?('"value":"aaaaaaaaaaaa"')
p coderange(str)

valid = "é"
p coderange(valid), coderange(valid * 3), coderange(valid * 0)
p coderange("ab".force_encoding(Encoding::UTF_16LE) * 2)
p coderange("ab".force_encoding(Encoding::UTF_16LE) * 0)
broken = "\xff".dup.force_encoding(Encoding::UTF_8)
p coderange(broken * 2)
p coderange("#{str}!"), coderange(123.to_s), coderange("abc".upcase)

kept = ["x#{1}", "é#{1}", "\xfe#{1}".dup.force_encoding(Encoding::UTF_8), "z#{1}".force_encoding(Encoding::UTF_16LE)]
p kept.map { |s| coderange(s) }
Process.warmup
p coderange(str)
p kept.map { |s| coderange(s) }
