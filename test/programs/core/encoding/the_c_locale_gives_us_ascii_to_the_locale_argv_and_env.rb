p Encoding.locale_charmap
p Encoding.find("locale")
p Encoding.default_external
p Encoding.find("external")
p Encoding.aliases["locale"]
p ENV["HOME"].encoding
p ENV.to_h.values.first.encoding
