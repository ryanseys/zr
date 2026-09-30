# `%#` changes a field's case as a whole -- all-uppercase becomes lowercase,
# anything else becomes uppercase -- rather than swapping it per character.
# Per-character swapcase gives "jANUARY" for "January", but CRuby answers
# "JANUARY". Only fields that are already uppercase (%p, %Z) agree.
t = Time.at(0).utc
p t.strftime("%#B")
p t.strftime("%#b")
p t.strftime("%#A")
p t.strftime("%#a")
p t.strftime("%#p")
p t.strftime("%#P")
p t.strftime("%#Z")
p t.strftime("%#j")
p t.strftime("%^a")
p t.strftime("%^B")
