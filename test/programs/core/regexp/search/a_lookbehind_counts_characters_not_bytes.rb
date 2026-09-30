# A lookbehind is measured and rewound in CHARACTERS, not bytes, as in CRuby.
# So a class or a `.` inside one matches a character of any width, and `.`
# is allowed there.
p("あb" =~ /(?<=[あい])b/ ? true : false)
p("ab" =~ /(?<=[ab])b/ ? true : false)
p("ab" =~ /(?<=[^x])b/ ? true : false)
p("あb" =~ /(?<=[^x])b/ ? true : false)
p("ab" =~ /(?<=.)b/ ? true : false)
p("あb" =~ /(?<=.)b/ ? true : false)
p("あいb" =~ /(?<=あい)b/ ? true : false)
p("あb" =~ /(?<!あ)b/ ? true : false)
p("いb" =~ /(?<!あ)b/ ? true : false)
p "aあb".sub(/(?<=あ)b/, "-")
p "aあbあb".gsub(/(?<=あ)b/, "-")
p("あいうb".match(/(?<=..)うb/) ? true : false)
p "xyz".match(/(?<=xy)z/)[0]
p("b" =~ /(?<=a)b/ ? true : false)
