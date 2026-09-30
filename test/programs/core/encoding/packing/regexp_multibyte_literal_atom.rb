# A multibyte character in a regexp literal is one atom, so a quantifier
# binds to the whole character: /あ+/ repeats "あ", not its last byte.
p("ああ" =~ /あ+/ ? $~[0] : nil)
p("ああ" =~ /あ{2}/ ? true : false)
p "ああxあ".scan(/あ+/)
p "ĀĀ".match(/Ā+/)[0]
p "ĀĀ".match?(/Ā{2}/)
p("あか" =~ /あ|か/ ? $~[0] : nil)
p("aあb" =~ /a.b/ ? true : false)
p "aあbあc".gsub(/あ/, "-")
p("ああ" =~ /\あ+/ ? $~[0] : nil)
p "あいう".index(/い/)
