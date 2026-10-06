pl = "żółć gęś"
w = pl.encode("Windows-1250")
p w.bytes
p w.encoding.name
p w.encode("UTF-8") == pl
r = "привет".encode("Windows-1251")
p r.bytes
p r.encode("KOI8-R").bytes
p "€uro".encode("ISO-8859-15").bytes
b = 0x81.chr.force_encoding("Windows-1252")
begin; b.encode("UTF-8"); rescue Encoding::UndefinedConversionError => e; puts e.message; end
begin; b.encode("KOI8-R"); rescue Encoding::UndefinedConversionError => e; puts e.message; end
p b.encode("UTF-8", undef: :replace)
begin; "щ".encode("Windows-1252"); rescue Encoding::UndefinedConversionError => e; puts e.message; end
s = (0xE9.chr + 0x81.chr + "ab").force_encoding("Windows-1252")
p s
p (0xE9.chr + "ab").force_encoding("Windows-1252").encode("UTF-8")
