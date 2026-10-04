# instance_eval and class_eval with a String: the source and the file
# name convert with to_str, and the line with to_int.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

source = Object.new
def source.to_str = :symbol
show { Object.new.instance_eval(source) }
file = Object.new
def file.to_str = "file.rb"
show { Object.new.instance_eval("__FILE__", file) }
line = Object.new
def line.to_int = 15
show { Object.new.instance_eval("__LINE__", "f.rb", line) }
bad = Object.new
def bad.to_int = :symbol
show { Object.new.instance_eval("1", "f.rb", bad) }
show { String.class_eval("__LINE__", file, line) }
