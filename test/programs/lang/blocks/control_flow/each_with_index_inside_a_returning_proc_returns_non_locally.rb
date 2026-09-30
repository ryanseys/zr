# each_with_index inside a returning proc.
def index_of_twenty
  proc { [10, 20, 30].each_with_index { |v, i| return i if v == 20 }; -1 }.call
end
p index_of_twenty

