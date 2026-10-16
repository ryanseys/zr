# str_transcode0 opens no converter for ASCII text between two encodings
# that contain ASCII. Any other target needs one, and ruby has none for
# these encodings.
def t(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

%w[EUC-TW Emacs-Mule GB1988 MacJapanese Windows-1258 macCentEuro macThai].each do |name|
  text = "abc".dup.force_encoding(name)
  t("#{name} to UTF-8") { text.encode("UTF-8") }
  t("#{name} to ISO-8859-1") { text.encode("ISO-8859-1") }
  t("#{name} to UTF-16LE") { text.encode("UTF-16LE") }
  t("#{name} to UTF-32BE") { text.encode("UTF-32BE") }
  t("#{name} to UTF-16") { text.encode("UTF-16") }
  t("#{name} with xml") { text.encode("UTF-8", xml: :text) }
end
t("UTF-16LE to Emacs-Mule") { "abc".encode("UTF-16LE").encode("Emacs-Mule") }
t("UTF-8 to Emacs-Mule") { "abc".encode("Emacs-Mule").bytes }
t("Windows-1252 to UTF-16LE") { "abc".dup.force_encoding("Windows-1252").encode("UTF-16LE").bytes }
