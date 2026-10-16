# Enumerator#each calls the method it enumerates by name, as
# rb_block_call_kw does, with the arguments and keywords it keeps: a
# private method answers, and TracePoint hears the call.
def trace(label)
  events = []
  tp = TracePoint.new(:c_call) { |t| events << "#{t.defined_class}##{t.method_id}" }
  result = tp.enable { yield }
  puts "#{label}: #{events.join(" ")} => #{result.inspect}"
end

trace(:each_slice_enum) { [1, 2].each_slice(1).to_a }
trace(:extra_args) { [3, 1, 2].each_slice(2).each.to_a }

class Walk
  def initialize(items) = @items = items

  private

  def walk(step, by: 1)
    @items.each_slice(step) { |slice| yield slice.sum * by }
  end
end

trace(:private_with_keywords) { Walk.new([1, 2, 3, 4]).to_enum(:walk, 2, by: 10).to_a }
trace(:string_name) { Walk.new([5, 6]).enum_for("walk", 1).to_a }
kwargs = { by: 2 }
enum = Walk.new([1, 2]).to_enum(:walk, 1, **kwargs)
kwargs[:by] = 100
p enum.to_a, enum.to_a
