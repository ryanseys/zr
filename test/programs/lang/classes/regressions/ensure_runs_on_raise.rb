# When the body of a `begin..ensure..end` raises, the ensure
# clause must still run before the exception keeps propagating.

class T_ensure_runs_on_raise_C
  def initialize
    @cleanup = "no"
    @before_raise = 0
  end

  def f
    begin
      @before_raise = 1
      raise "boom"
    ensure
      @cleanup = "yes"
    end
  end

  def report
    begin
      f
    rescue => e
      puts e
    end
    puts @before_raise
    puts @cleanup
  end
end

T_ensure_runs_on_raise_C.new.report
