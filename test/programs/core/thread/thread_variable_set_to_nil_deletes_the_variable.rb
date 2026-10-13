# Thread#thread_variable_set with nil deletes the variable (ruby 4.1),
# so thread_variables and thread_variable? no longer see it.
th = Thread.current
p th.thread_variable_set(:a, 1)
p th.thread_variable_set("b", 2)
p th.thread_variables.sort & %i[a b]
p th.thread_variable_set(:a, nil)
p th.thread_variables.include?(:a)
p th.thread_variable?(:a)
p th.thread_variable_get(:a)
p th.thread_variable_set("b", nil)
p th.thread_variables.include?(:b)

# Deleting a variable that was never set is fine.
p th.thread_variable_set(:never, nil)
p th.thread_variables.include?(:never)

# false is a value, not a deletion.
th.thread_variable_set(:f, false)
p th.thread_variables.include?(:f)
p th.thread_variable?(:f)
p th.thread_variable_get(:f)

# A key that is no Symbol or String is a TypeError, even for nil.
begin
  th.thread_variable_set(1, nil)
rescue TypeError => e
  p [e.class, e.message]
end

# The variables of another thread.
t = Thread.new do
  Thread.current.thread_variable_set(:x, 1)
  Thread.current.thread_variable_set(:x, nil)
  Thread.current.thread_variables
end
p t.value

# A frozen thread refuses the write before it reads the key.
t = Thread.new { sleep }
Thread.pass until t.stop?
t.freeze
[[:a, 1], [:a, nil], [1, nil]].each do |key, value|
  t.thread_variable_set(key, value)
rescue FrozenError, TypeError => e
  p [e.class, e.message]
end
t.kill.join
