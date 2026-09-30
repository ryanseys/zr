# `begin..rescue..ensure..end` — when the rescue body exits via
# `return`, the ensure clause must still run before the function
# returns.

class T_ensure_runs_on_return_from_rescue_C
  def initialize
    @cleanup = "no"
  end

  def f
    begin
      raise "boom"
    rescue
      return 99
    ensure
      @cleanup = "yes"
    end
  end

  def report
    puts f
    puts @cleanup
  end
end

T_ensure_runs_on_return_from_rescue_C.new.report
