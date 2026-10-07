# CRuby keeps a String's coderange (7bit, valid, broken or unknown) in its
# flags: a literal has it from the compiler, a copy takes it from its
# source, and a new encoding or a write makes it unknown until a scan.
# ObjectSpace.dump writes it, and Process.warmup scans every String. zr
# caches the scans it makes (FL_ASCII, FL_VALID, FL_SCANNED), but sets no
# coderange where CRuby's compiler or copies do, so its dump computes the
# coderange and never writes "unknown".
require "objspace"

def coderange(s) = ObjectSpace.dump(s)[/"coderange":"(\w+)"/, 1]

str = "a" * 12
p coderange(str)
str.force_encoding(Encoding::UTF_16LE)
str.force_encoding(Encoding::BINARY)
p coderange(str)
Process.warmup
p coderange(str)
p coderange("#{str}!")
p coderange(123.to_s)
p coderange("abc".upcase)
