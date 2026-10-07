# Enumerator#inspect shows its arguments in parentheses. A last argument
# that is a Hash, not empty, with only Symbol keys shows as keywords, each
# key and value as to_s gives it (append_method).
p (0..10).each_cons(2), (0..10).each_with_object({}), (0..10).each_with_object(a: 1)
p (0..10).each_with_object({ a: 1 })
p (0..1).each_with_object(a: "x"), (0..1).each_with_object({ "s" => 1 }), (0..1).each_with_object({ a: 1, "s" => 2 })
p (0..1).each_with_object(a: nil, b: :c)
p [1].each_slice(2)
o = Object.new
def o.inspect = "o"
def o.each(*, **) = nil
p o.to_enum(:each, 1, k: [1, "y"]), o.to_enum(:each, { a: 1 }), o.to_enum(:each, 1, {}), o.enum_for(:each, "x y": 1)
args = [1, { b: 2 }]
e = o.to_enum(:each, *args)
p e, args
a = []
en = a.each_with_object(a)
a << en
p en
