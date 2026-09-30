def lazily
  [1, 2, 3].lazy.map { |x| x * 2 }.each { |v| yield v }
  :fell
end
def c4; lazily { |v| return v }; :no; end
p c4

