class T_ivar_or_write_basic_T
  def initialize
    @str = nil
    @hits = 0
    @marker = "init"
  end

  def cache
    @str ||= compute
  end

  def compute
    @hits += 1
    "hello"
  end

  def get
    @str
  end

  def hits
    @hits
  end
end

t = T_ivar_or_write_basic_T.new
puts t.get.nil? ? "nil-before" : "not-nil-before"
puts t.cache
puts t.get
puts t.cache
puts t.get
puts "hits=#{t.hits}"

class T_ivar_or_write_basic_U
  def initialize
    @v = nil
    @hits = 0
    @log = []
  end

  def value
    @v ||= 42
  end

  def hits
    @hits
  end

  def log_size
    @log.size
  end
end

u = T_ivar_or_write_basic_U.new
puts u.value
puts u.value
puts u.value
