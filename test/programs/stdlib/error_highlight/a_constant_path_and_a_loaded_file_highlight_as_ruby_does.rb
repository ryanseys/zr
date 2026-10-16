# A constant path is one instruction, so a NameError in any of its parts
# highlights the part that has the error's name, or none when two parts
# have it; a file that a load compiles at run time is highlighted too, as
# ruby parses it again when the error is shown.
require "tempfile"
def show
  yield
rescue Exception => e
  puts e.detailed_message(highlight: false).sub(/\A.*?: /, ""), "--"
end
module Holder
  module Inner; end
  Nil = nil
end
show { Holder::NotDefined::NotDefined }
show do
  Holder::
    NotDefined += 1
end
show { Holder::Nil += 1 }
show do
  nil.foo + 1
rescue NoMethodError => exc
  def exc.backtrace_locations = []
  raise
end
Tempfile.create(["eh", ".rb"], binmode: true) do |tmp|
  tmp << "1.time {}"
  tmp.close
  show { load tmp.path }
end
Tempfile.create(["eh", ".rb"], binmode: true) do |tmp|
  tmp << "\t \t1.time {}\n"
  tmp.close
  show { load tmp.path }
end
Tempfile.create(["eh", ".rb"], binmode: true) do |tmp|
  tmp << "x = nil\nx.size\n"
  tmp.close
  show { load tmp.path }
end

show { Holder::NotDefined::Other }
show { Holder::Inner::NotDefined }
show { Holder::NotDefined }
show { NotDefined::Other }
show { ::NotDefined::Other }
show { Holder::NotDefined::NotDefined::X }
show { Holder::
  NotDefined }
