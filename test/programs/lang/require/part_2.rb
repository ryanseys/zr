# lrama-required features, in three parts of one coverage matrix.



# A9: Hash#merge (String keys, Integer values)
mrg1 = {"a" => 1, "b" => 2}
mrg2 = {"b" => 3, "c" => 4}
mrg3 = mrg1.merge(mrg2)
puts mrg3["a"]  # 1
puts mrg3["b"]  # 3  (mrg2 overrides mrg1)
puts mrg3["c"]  # 4

# A19: Array#dup
arr_dup = [10, 20, 30]
arr_dup2 = arr_dup.dup
puts arr_dup2[0]  # 10
puts arr_dup2.length  # 3

# A19: String#dup (const string)
sd1 = "hello"
sd2 = sd1.dup
puts sd2  # hello

# A20: Hash.new(0) with default value
counter = Hash.new(0)
counter["x"] = counter["x"] + 1
counter["x"] = counter["x"] + 1
counter["y"] = counter["y"] + 1
puts counter["x"]  # 2
puts counter["y"]  # 1
puts counter["z"]  # 0 (default)

# B2: attr_writer
class Writer
  attr_reader :name
  attr_writer :name
  def initialize(n)
    @name = n
  end
end
w = Writer.new("before")
puts w.name  # before
w.name = "after"
puts w.name  # after

# B3: Comparable (include Comparable + def <=>)
class Weight
  include Comparable
  attr_reader :grams
  def initialize(g)
    @grams = g
  end
  def <=>(other)
    @grams - other.grams
  end
end
w1 = Weight.new(100)
w2 = Weight.new(200)
w3 = Weight.new(100)
puts w1 < w2    # true
puts w2 > w1    # true
puts w1 == w3   # true
puts w1 > w2    # false
puts w1 <= w3   # true
puts w2 >= w1   # true

puts "done"
