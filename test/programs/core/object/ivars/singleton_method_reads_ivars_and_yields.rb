obj = Object.new
obj.instance_variable_set(:@base, 100)
def obj.add
  @base + yield
end
p obj.add { 5 }
