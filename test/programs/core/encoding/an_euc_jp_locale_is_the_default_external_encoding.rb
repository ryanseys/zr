p Encoding.locale_charmap
p Encoding.find("locale")
p Encoding.default_external
p ENV["HOME"].encoding
Encoding.default_external = "UTF-8"
p Encoding.default_external, Encoding.find("locale")
