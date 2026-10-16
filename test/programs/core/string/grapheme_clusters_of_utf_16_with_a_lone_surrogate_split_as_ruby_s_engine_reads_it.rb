def t(label, bytes, encoding)
  s = bytes.dup.force_encoding(encoding)
  puts "#{label}: #{s.grapheme_clusters.map(&:bytes).inspect}"
  puts "  each: #{s.each_grapheme_cluster.size} #{s.each_grapheme_cluster.to_a == s.grapheme_clusters}"
end

t("lone lead le", "a\x00\x00\xD8b\x00", "UTF-16LE")
t("lone lead be", "\x00a\xD8\x00\x00b", "UTF-16BE")
t("lone trail le", "a\x00\x00\xDCb\x00", "UTF-16LE")
t("lone trail be", "\x00a\xDC\x00\x00b", "UTF-16BE")
t("lead at the end", "a\x00\x00\xD8", "UTF-16LE")
t("two leads", "\x00\xD8\x00\xD8b\x00", "UTF-16LE")
t("a pair", "a\x00\x3D\xD8\x00\xDEb\x00", "UTF-16LE")
t("a pair be", "\x00a\xD8\x3D\xDE\x00\x00b", "UTF-16BE")
t("odd tail", "a\x00b", "UTF-16LE")
t("combining after a lone lead", "\x00\xD8\x01\x03", "UTF-16LE")
t("crlf", "\r\x00\n\x00a\x00", "UTF-16LE")
t("utf-32 surrogate", "a\x00\x00\x00\x00\xD8\x00\x00b\x00\x00\x00", "UTF-32LE")
t("utf-32 past unicode", "\x00\x00\x11\x00a\x00\x00\x00", "UTF-32BE")
t("utf-32 past unicode le", "\x00\x00\x11\x00a\x00\x00\x00", "UTF-32LE")
t("utf-32 short tail", "a\x00\x00\x00b\x00", "UTF-32LE")
t("empty", "", "UTF-16LE")
