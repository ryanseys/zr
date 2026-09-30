# CRuby folds two String literals and newrange into one static
# Range unless a label stands before the first string: a block's
# body, a loop's body, an if's else arm, an unless's then arm and a
# body a rescue covers.
def two = [yield, yield].then { |a, b| a.equal?(b) ? :static : :fresh }
def m1 = ("a".."b")
def m2
  ("a".."b")
end
def m3(c) = c ? ("a".."b") : ("c".."d")
def m4(c)
  if c then ("a".."b") else ("c".."d") end
end
def m5(c)
  case c when 1 then ("a".."b") else ("c".."d") end
end
def m6
  begin
    ("a".."b")
  rescue
    nil
  end
end
def m7
  i = 0
  r = nil
  while i < 1
    r = ("a".."b")
    i += 1
  end
  r
end
def m8(c) = (c && ("a".."b"))
def m9 = [1, ("a".."b")]
def m10 = [("a".."b"), 1]
def m11 = ("a".."b").itself
def m12 = (x = ("a".."b"))
def m13 = -> { ("a".."b") }
def m14 = (true; ("a".."b"))
p m1.equal?(m1), m2.equal?(m2)
p m3(true).equal?(m3(true)), m3(false).equal?(m3(false))
p m4(true).equal?(m4(true)), m4(false).equal?(m4(false))
p m5(1).equal?(m5(1)), m5(2).equal?(m5(2))
p m6.equal?(m6), m7.equal?(m7), m8(true).equal?(m8(true))
p m9[1].equal?(m9[1]), m10[0].equal?(m10[0]), m11.equal?(m11), m12.equal?(m12)
l = m13; p l.().equal?(l.())
p m14.equal?(m14)
def c1(c)
  case c
  in 1 then ("a".."b")
  else ("c".."d")
  end
end
def c2(c)
  case c
  when 1 then 2
  else ("c".."d")
  end
end
def c3(c)
  case
  when c then 1
  else ("c".."d")
  end
end
def c4(c)
  unless c then ("a".."b") else ("c".."d") end
end
p c1(1).equal?(c1(1)), c1(2).equal?(c1(2)), c2(2).equal?(c2(2)), c3(false).equal?(c3(false)), c4(false).equal?(c4(false)), c4(true).equal?(c4(true))
