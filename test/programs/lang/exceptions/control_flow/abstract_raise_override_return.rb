# A base method that always raises can have an override in a subclass that
# returns a value. A call in value position gives the override's value.
module Helper
  def self.find(t); t.to_s; end
end
class Base
  def self.table_name; raise "abstract"; end
  def self.lookup; Helper.find(table_name); end
end
class Article < Base
  def self.table_name; "articles"; end
  def self.lookup; 0; end
end
puts Article.lookup

# instance method, two overrides of divergent types -> unified poly
class Shape
  def area; raise "abstract"; end
  def describe; "area=#{area}"; end
end
class Sq < Shape
  def area; 4; end
end
class Nm < Shape
  def area; "n/a"; end
end
puts Sq.new.describe
puts Nm.new.describe
