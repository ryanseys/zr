# xml: :attr escapes the apostrophe as &apos;, as enc/trans/escape.trans
# does, both through String#encode and through a Converter.

p "a'b\"<&>".encode(xml: :attr)
p "a'b\"<&>".encode(xml: :text)
p "a'b".encode("UTF-16LE", xml: :attr).encode("UTF-8")
ec = Encoding::Converter.new("UTF-8", "EUC-JP", xml: :attr)
p ec.convert("it's")
p ec.finish

