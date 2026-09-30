# Under /i, the backreference comparison ignores case, like the rest of the
# pattern. Folding stops at ASCII, as it does everywhere else here.
p("aA" =~ /(a)\1/i ? true : false)
p("aA" =~ /(a)\1/ ? true : false)
p("abAB" =~ /(ab)\1/i ? true : false)
p("aa" =~ /(a)\1/ ? true : false)
p("aA" =~ /(a)\k<1>/i ? true : false)
p("aA".match(/(?<g>a)\k<g>/i)[0])
p("aA".match(/(?'g'a)\k'g'/i)[0])
p "xAxa".scan(/(a)\1/i).size
p("ÄÄ" =~ /(Ä)\1/i ? true : false)
