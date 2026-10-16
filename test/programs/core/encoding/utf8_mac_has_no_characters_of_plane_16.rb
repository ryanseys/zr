# Ruby's UTF-8 to UTF8-MAC table has no lead byte F4, so a character of
# plane 16 is undefined in UTF8-MAC.
def t(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

t("raise") { "a\u{10FFFF}".encode("UTF8-MAC") }
t("first of plane 16") { "\u{100000}".encode("UTF8-MAC") }
t("error") do
  "a\u{10FFFF}".encode("UTF8-MAC")
rescue Encoding::UndefinedConversionError => e
  [e.error_char, e.source_encoding, e.destination_encoding]
end
t("replace") { "a\u{10FFFF}é".encode("UTF8-MAC", undef: :replace, replace: "Z").bytes }
t("default replace") { "\u{10FFFD}x".encode("UTF8-MAC", undef: :replace).bytes }
t("xml") { "a\u{10FFFF}".encode("UTF8-MAC", xml: :text).bytes }
t("fallback") { "é\u{100000}".encode("UTF8-MAC", fallback: { "\u{100000}" => "Q" }).bytes }
t("plane 15") { "\u{FFFFF}é".encode("UTF8-MAC").bytes }
t("from latin1") { "caf\xE9".dup.force_encoding("ISO-8859-1").encode("UTF8-MAC").bytes }
t("from UTF-16LE") { "a\u{10FFFF}".encode("UTF-16LE").encode("UTF8-MAC") }
t("back") { "é".encode("UTF8-MAC").encode("UTF-8") }
