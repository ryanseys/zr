# A regexp literal with a bad escape or multibyte character is a
# SyntaxError when eval compiles it, also in a fragment of an
# interpolated regexp. A fragment that is no whole pattern is no error.
def t(name)
  r = yield
  puts "#{name}: #{r.inspect}"
rescue Exception => e
  puts "#{name}: #{e.class}: #{e.message.lines.first.chomp.sub(/\(eval at [^)]*\)/, "(eval)")}"
end
t("no-encoding unicode") { eval('/\u{6666}/n') }
t("euc unicode") { eval('/\u{6666}/e') }
t("sjis unicode") { eval('/\u{6666}/s') }
t("utf-8 unicode") { eval('/\u{6666}/u').source }
t("short tail") { eval('/#{ }\xc2/u') }
t("short head") { eval('/\xc2#{ }/u') }
t("split escape") { eval('/\xc2#{ }\xa1/u') }
t("whole escape") { eval('/#{ }\xc2\xa1/u').source }
t("sjis short") { eval('/\x81#{ }/s') }
t("euc short") { eval('/\xc2#{ }/e') }
t("string literal piece") { eval('/#{"\xcd"}/') }
t("open group") { eval('/(#{1})/').source }
t("runtime pieces") { s1, s2 = "\xc2", "\xa1"; /#{s1}#{s2}/ }
