# Through an Enumerator, and through a lazy chain.
def three
  Enumerator.new { |y| y << 1; y << 2 }.each { |v| yield v }
  :fell
end
def c3; three { |v| return v }; :no; end
p c3

