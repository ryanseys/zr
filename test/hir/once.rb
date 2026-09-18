END { p :last }
BEGIN { p :first }

def match(pattern, subject)
  subject =~ /#{pattern}/o
end
p match("a", "abc")
p match("z", "abc")

x = "b"
p(/#{x}/o.source)
p :body
