class E < StandardError
  def detailed_message(highlight: false, **opt) = "#{message} #{opt.inspect} #{highlight}"
end
e = E.new("m")
p e.full_message(foo: 1)
p e.full_message(highlight: false, order: :top, bar: 2)
p RuntimeError.new("").full_message(highlight: false)
p ArgumentError.new("").full_message(highlight: true)
e = RuntimeError.new("r")
e.set_backtrace(["a:1", "b:2", "c:3"])
p e.full_message(highlight: false, order: :bottom)
class B < StandardError
  def backtrace = ["over:1", "over:2"]
end
p B.new("b").full_message(highlight: false)
class D < StandardError
  def detailed_message(**) = raise("inner")
end
raise D, "x"
