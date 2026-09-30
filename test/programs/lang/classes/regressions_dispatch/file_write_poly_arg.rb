# The cycle this program builds on purpose, and the census it leaves
# behind. A cycle alive at exit is not a defect: it is a ring the
# program never broke, so the census below is recorded as an
# observation rather than gated on.
#
# An Outer and its inherited Sub hold each other through the forwarded class-method init.
# At exit: cycle leak: 2 objects (T_forward_call_class_method_inherited_init_Outer x1, T_forward_call_class_method_inherited_init_Sub x1)
# Bundled tests:
#   - fiber_ivar_persists_across_yield
#   - fiber_yield_across_method_call
#   - file_write_poly_arg
#   - forward_call_class_method_inherited_init
#   - forward_call_class_method_inherited_init_int_array


# `File.write(path, value)` where `value` comes from a call on objects
# of two classes. Each `run` returns a String, and File.write writes it.

class T_file_write_poly_arg_Worker
  def run(x)
    "result-#{x}"
  end
end

class T_file_write_poly_arg_OtherWorker
  def run(x)
    "alt-#{x}"
  end
end

# An Array of objects of two classes — both classes' `run` returns a
# String.
workers = [T_file_write_poly_arg_Worker.new, T_file_write_poly_arg_OtherWorker.new]
results = workers.map { |w| w.run(42) }

# results[0] is the String from the first worker.
# Use a cwd-relative path, because Windows MinGW has no `/tmp`.
path = "spinel_i643_test.txt"
File.write(path, results[0])
puts File.read(path)
File.delete(path)
