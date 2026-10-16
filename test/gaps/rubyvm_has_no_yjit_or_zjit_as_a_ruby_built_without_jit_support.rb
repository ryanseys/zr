# zr answers as a ruby built without JIT support: neither RubyVM::YJIT
# nor RubyVM::ZJIT exists (vm.c's empty Init_builtin_yjit and
# Init_builtin_zjit), and --jit, --yjit and --zjit only warn. The
# reference ruby has YJIT and ZJIT, so it defines both, with their
# readers saying that neither is on.
p defined?(RubyVM::YJIT), defined?(RubyVM::ZJIT)
p RubyVM.constants.grep(/JIT/).sort
p defined?(RubyVM::YJIT.enable)
begin
  y = RubyVM::YJIT
  p [y.enabled?, y.stats_enabled?, y.log_enabled?, y.runtime_stats, y.exit_locations]
rescue NameError => e
  p e.class
end
