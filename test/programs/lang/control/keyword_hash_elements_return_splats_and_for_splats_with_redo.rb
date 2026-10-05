# Forms that zr refused: a keyword hash as an array element under
# defined?, splats and a double splat in return, and a splat as a for target.
p defined?([a: [:b, :c]]), defined?([*b]), defined?([1, k: 2])
def ret(*args, **kwargs) = (return *args, *args, **kwargs)
p ret(1, foo: 0), ret(1), ret
r = []
for *x in [[1, 2], [3, 4]] do; r << x; end
p r
r = []
for * in [[1, 2], [3, 4]] do; r << :ok; end
p r
r = []
for x, *y in [[1, 2, 3], [4]] do; r << [x, y]; end
p r
# `redo` in a for loop runs the body again with the variable as it is.
seen = []
for i in 1..5
  seen << i
  if i == 3
    i = 0
    redo
  end
end
p seen
seen = []
for i in [1, 2, 3]
  seen << i
  if i == 2
    i = 9
    redo
  end
end
p seen
counter = 0
5.times do |i|
  counter += 1
  redo if i == 2 && counter < 3
end
p counter
