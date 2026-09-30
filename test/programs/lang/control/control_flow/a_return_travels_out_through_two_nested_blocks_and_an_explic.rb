# Through two nested blocks and an explicit `&b`.
def two(&b)
  [1, 2].each { |x| [3, 4].each { |y| b.call(x * y) } }
  :fell
end
def c2; two { |v| return v }; :no; end
p c2

