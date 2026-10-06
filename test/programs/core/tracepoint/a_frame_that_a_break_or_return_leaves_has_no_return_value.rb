# A frame that a break or a return leaves on the way to its target has
# no return value: its :return or :b_return event shows nil. The block
# that breaks shows the break's value, and the target returns as usual.
class T
  def f_raise
    raise
  rescue
    return :f_raise_return
  end
  def f_iter1
    yield
    return :f_iter1_return
  end
  def f_iter2
    yield
    return :f_iter2_return
  end
  def f_return_in_iter
    f_iter1 do
      f_iter2 do
        return :f_return_in_iter_return
      end
    end
    2
  end
  def f_break_in_iter
    f_iter1 do
      f_iter2 do
        break :f_break_in_iter_break
      end
      :f_iter1_block_value
    end
    :f_break_in_iter_return
  end
  define_method(:f_last_defined) { :f_last_defined }
  define_method(:f_return_defined) { return :f_return_defined }
  define_method(:f_break_defined) { break :f_break_defined }
  define_method(:f_raise_defined) do
    raise
  rescue
    return :f_raise_defined
  end
  define_method(:f_break_in_rescue_defined) do
    raise
  rescue
    break :f_break_in_rescue_defined
  end
  define_method(:just_yield) { |&block| block.call }
  define_method(:unwind_multiple_bmethods) do
    just_yield { return :unwind_multiple_bmethods }
  end
  def f_iter = yield
  def f_break_in_rescue
    f_iter do
      begin
        raise
      rescue
        break :b
      end
    end
    :f_break_in_rescue_return_value
  end
  def each_loop_break = [1, 2].each { |x| break x * 10 }
  def tp_return_value(m)
    events = []
    TracePoint.new(:return, :b_return) { |tp| events << [tp.event, tp.method_id, tp.return_value] }.enable { send(m) }
    events
  end
end
t = T.new
%i[f_raise f_return_in_iter f_break_in_iter f_last_defined f_return_defined f_break_defined f_raise_defined
   f_break_in_rescue_defined unwind_multiple_bmethods f_break_in_rescue each_loop_break].each do |m|
  p [m, t.tp_return_value(m)]
end
