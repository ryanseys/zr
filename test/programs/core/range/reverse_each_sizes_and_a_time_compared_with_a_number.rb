# A beginless reverse_each down from an Integer is endless. A Time
# compares with a number through the number's <=>, which asks the Time
# for coerce.
p (..3).reverse_each.size, (1..3).reverse_each.size, ('a'..'z').reverse_each.size
p((1..).reverse_each.size rescue $!)
t = Time.at(1)
def t.respond_to?(*) = (($r ||= 0); $r += 1; false)
p (t <=> 2), (2 <=> t), $r, (Time.at(1) <=> 1.5), (Time.at(1) <=> Time.at(2))
