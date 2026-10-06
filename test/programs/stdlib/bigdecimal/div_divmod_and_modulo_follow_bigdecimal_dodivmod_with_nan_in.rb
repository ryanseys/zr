# div, divmod and % follow BigDecimal_DoDivmod with NaN, an infinity and
# zero on either side.
require "bigdecimal"
one, nan, inf = BigDecimal("1"), BigDecimal("NaN"), BigDecimal("Infinity")
[[:div, 1], [:div, 0], [:%, inf], [:%, -inf], [:%, 0], [:divmod, inf], [:divmod, -inf], [:remainder, inf]].each do |op, arg|
  [one, -one, nan, inf, BigDecimal("0")].each do |x|
    result = begin
      x.send(op, arg)
    rescue => e
      e.class
    end
    p [x, op, arg, result]
  end
end
