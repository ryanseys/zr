# Through several frames, and through `__send__`.
def deep3(&b) = deep2(&b)
def deep2(&b) = deep1(&b)
def deep1(&b)
  [1, 2].each { |x| b.call(x) }
  :fell
end
def c8; deep3 { |v| return v }; :no; end
p c8

