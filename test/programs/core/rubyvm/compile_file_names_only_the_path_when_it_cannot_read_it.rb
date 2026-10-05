# compile_file reads the file as pm_load_file does: an error names the path
# alone, and a path that is no String is a TypeError.
begin
  RubyVM::InstructionSequence.compile_file_prism("idontexist.rb")
rescue SystemCallError => e
  p e.class, e.message
end
p((RubyVM::InstructionSequence.compile_file_prism(nil) rescue $!))
