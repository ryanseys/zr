# `def initialize(conf = ARGV)` with a caller that passes a String.
# `conf` holds that String, so `@s.length` gives the String's length.

class T_default_argv_narrows_from_string_call_site_Wrapper
  def initialize(s)
    @s = s
  end
  def show
    puts @s.length
  end
end

class T_default_argv_narrows_from_string_call_site_Entry
  def initialize(conf = ARGV)
    @conf = T_default_argv_narrows_from_string_call_site_Wrapper.new(conf)
  end
  def show
    @conf.show
  end
end

T_default_argv_narrows_from_string_call_site_Entry.new("hello").show     # 5
