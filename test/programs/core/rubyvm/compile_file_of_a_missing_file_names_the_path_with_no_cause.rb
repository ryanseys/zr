# InstructionSequence.compile_file raises the system's error naming the
# path alone, as pm_load_file does, with no cause from a read inside it.
[:compile_file, :compile_file_prism].each do |name|
  RubyVM::InstructionSequence.public_send(name, "idontexist.rb")
rescue SystemCallError => e
  p [name, e.class, e.message, e.cause, e.backtrace_locations.map(&:label)]
end
