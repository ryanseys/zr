# Nested `begin..ensure..end` — a `return` inside the inner begin
# must replay the inner ensure first, then the outer ensure, then
# return. Both writebacks must take effect, in order.

class T_ensure_runs_on_return_nested_T
  def initialize
    @inner = 0
    @outer = 0
    @log = ""
  end

  def run
    begin
      a = 1
      begin
        b = 10
        a = 2
        return
      ensure
        @inner = b
        @log = @log + "i"
      end
    ensure
      @outer = a
      @log = @log + "o"
    end
  end

  def report
    run
    puts "inner=" + @inner.to_s
    puts "outer=" + @outer.to_s
    puts "log=" + @log
  end
end

T_ensure_runs_on_return_nested_T.new.report
