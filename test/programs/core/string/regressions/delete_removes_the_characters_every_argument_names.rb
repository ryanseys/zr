# String#delete with multiple args deletes the intersection of the
# charsets (each arg is a charset spec).
p "hello".delete("l", "o")
p "hello".delete("lo", "l")
p "hello".delete("l", "h", "e")
p "hello".delete("el", "ello")
p "hello".delete("l")
p "hello".delete("^l")
