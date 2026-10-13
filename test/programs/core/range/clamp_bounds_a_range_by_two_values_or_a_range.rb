# ruby 4.1's Range#clamp (Feature #22175): a new Range of the bounds
# clamped to a min and a max, or to a range's begin and end. The end
# stays excluded where the end it took was, and a range wholly past one
# side is empty.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect} #{r.frozen? if r.is_a?(Range)}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
t("1") { (1..10).clamp(3, 7) }
t("2") { (1...10).clamp(3, 7) }
t("3") { (1...10).clamp(3, 10) }
t("4") { (0...).clamp(0, 10) }
t("5") { (1..10).clamp(3..7) }
t("6") { (1..10).clamp(3...7) }
t("7") { (1..5).clamp(3...7) }
t("8") { (..10).clamp(3, 7) }
t("9") { (...10).clamp(3, 7) }
t("10") { (..10).clamp(3...7) }
t("11") { (..5).clamp(3...7) }
t("12") { (1..10).clamp(20..30) }
t("13") { (1..10).clamp(-10..0) }
t("14") { (..10).clamp(20..30) }
t("15") { (1..10).clamp(..7) }
t("16") { (1..10).clamp(...7) }
t("17") { (1..5).clamp(...7) }
t("18") { (1..10).clamp(3..) }
t("19") { (1..10).clamp(3...) }
t("20") { (1..).clamp(3..) }
t("21") { (1...).clamp(3...) }
t("nil nil") { (1..10).clamp(nil, nil) }
t("nil..nil") { (1..10).clamp(nil..nil) }
t("min>max") { (1..10).clamp(7, 3) }
t("min>max r") { (1..10).clamp(7..3) }
t("bad type") { (1..10).clamp(5) }
t("nil arg") { (1..10).clamp(nil) }
t("aseq") { (1..10).clamp(1.step(5)) }
t("strings") { ("a".."z").clamp("c", "f") }
t("floats") { (1.5..9.5).clamp(2, 3.5) }
t("mixed") { (1..10).clamp("a", "b") }
t("mixed2") { (1..10).clamp(2, "b") }
t("no args") { (1..10).clamp }
t("3 args") { (1..10).clamp(1, 2, 3) }
o = Object.new
def o.begin = 2
def o.end = 4
def o.exclude_end? = true
t("duck") { (1..10).clamp(o) }
class MyR < Range; end
t("sub") { MyR.new(1, 10).clamp(2, 3).class }
t("sub arg") { (1..10).clamp(MyR.new(2, 3, true)) }
t("equal") { (1..10).clamp(10, 10) }
t("equal excl") { (1...10).clamp(10, 10) }
t("point") { (5..5).clamp(1, 3) }
t("empty") { (5...5).clamp(1, 9) }
t("arity") { Range.instance_method(:clamp).arity }
t("frozen") { (1..10).clamp(2, 3).frozen? }
