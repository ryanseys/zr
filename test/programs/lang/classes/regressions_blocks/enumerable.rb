class T_enumerable_NumberList
  include Enumerable
  def initialize
    @data = (1..5).to_a
  end
  def each
    @data.each do |x|
      yield x
    end
  end
end

list = T_enumerable_NumberList.new
total = 0
list.each do |x|
  total += x
end
puts total  # 15
puts "done"
