# File.fnmatch compares a bracket range by code points, as rb_enc_codepoint
# reads them, so an invalid byte where the range reads a character raises
# ArgumentError; a byte that matches by its bytes first, or a binary
# string, does not.
def try(pattern, string, flags = 0)
  p [pattern, string, File.fnmatch(pattern, string, flags)]
rescue ArgumentError => e
  p [pattern, string, e.message]
end

try("[a-z]", "\xe3")
try("[a-z]", "\xe3".b)
try("[a-\xe3]", "b")
try("[\xe3-z]", "b")
try("x[a-z]", "x\xe3y")
try("[!a-z]", "\xe3")
try("[a]", "\xe3")
try("[\xe3]", "\xe3")
try("[\xe3-z]", "\xe3")
try("[a-z]", "\xe3\x81\x82")
try("[a-z]", "あ")
try("[ぁ-ん]", "あ")
try("?", "\xe3")
try("*", "\xe3\xe3")
try("[a-z]", "Q", File::FNM_CASEFOLD)
try("[A-Z]", "q", File::FNM_CASEFOLD)
try("[a]", "\xe3", File::FNM_CASEFOLD)
try("a", "\xe3", File::FNM_CASEFOLD)
try("[a-z]", "\xe3".force_encoding("EUC-JP"))
