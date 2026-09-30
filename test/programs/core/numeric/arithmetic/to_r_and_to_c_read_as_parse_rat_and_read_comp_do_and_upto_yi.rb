p "1/2.5".to_r, "1_000.5_5".to_r, "1__2".to_r, ".5".to_r
p "1+2j".to_c, "1+2I".to_c, "Infinity".to_c
p Rational(".5")
begin
  Rational("1.e3")
rescue ArgumentError => e
  p e.message
end
p "aa".upto("b").to_a, ("a9".."b").to_a
