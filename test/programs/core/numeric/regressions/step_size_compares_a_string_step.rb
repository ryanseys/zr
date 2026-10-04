# Numeric#step without a block: an Enumerator whose size compares the
# step with zero, which a String cannot do.
[[1, 5, "1"], [1.1, 5.1, "foo"]].each do |from, to, by|
  e = from.step(to, by)
  p e.class
  begin
    e.size
  rescue ArgumentError => error
    p error.message
  end
end
