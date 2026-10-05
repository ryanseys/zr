# CRuby frees the method entry of a method that a later define_method
# replaces or remove_method removes. zr allocates a frame record for each
# define_method call (zr_meta_at) and never frees it, as frames and
# backtrace rows point to it, so a loop of define_method grows about 190
# bytes a call (test_alias.rb's test_alias_memory_leak).
def rss_kb = Integer(IO.popen(["ps", "-o", "rss=", "-p", Process.pid.to_s], &:read).strip)

class A
  def self.churn
    200.times do
      1000.times { |i| define_method(:"m_#{i}") {} }
      GC.start
    end
  end
end
A.churn
before = rss_kb
A.churn
p rss_kb - before < 10_000
