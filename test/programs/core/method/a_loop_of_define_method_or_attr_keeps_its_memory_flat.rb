# A method that a later define_method or attribute replaces with one of
# the same name, at the same place, gives back its memory: a loop of
# definitions does not grow (test_alias.rb's test_alias_memory_leak).
def rss_kb = Integer(IO.popen(["ps", "-o", "rss=", "-p", Process.pid.to_s], &:read).strip)

class A
  def self.churn
    200.times do
      1000.times do |i|
        define_method(:"m_#{i}") {}
        attr_accessor :"a_#{i}"
      end
      GC.start
    end
  end
end
A.churn
before = rss_kb
A.churn
p rss_kb - before < 10_000
p A.new.m_1, A.instance_method(:a_2).source_location.last
