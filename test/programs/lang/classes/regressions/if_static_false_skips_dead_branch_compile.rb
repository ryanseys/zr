# A predicate that reads an ivar only ever assigned `nil` is always
# false. The body never runs, so a call in it that needs a String
# (as `sub("MODE", @mode)`) does not stop the program.

class T_if_static_false_skips_dead_branch_compile_Profiler
  def initialize
    # `@mode` is always nil — only ever assigned this literal.
    # So the predicate below is always false.
    @mode = nil
  end

  def run
    # Dead branch when @mode is nil. `sub` with a nil argument
    # would raise TypeError, but this body never runs.
    if @mode
      out = "label_MODE".sub("MODE", @mode)
      puts out
    end
    puts "ran"
  end
end

# `if @nil_ivar; ... else; ... end` with a trailing stmt puts
# the if in statement position. The else arm runs when the
# predicate is always nil.
class T_if_static_false_skips_dead_branch_compile_Either
  def initialize
    @verbose = nil
  end

  def run
    if @verbose
      out = "label_MODE".sub("MODE", @verbose)
      puts out
    else
      puts "quiet"
    end
    puts "done"
  end
end

T_if_static_false_skips_dead_branch_compile_Profiler.new.run
T_if_static_false_skips_dead_branch_compile_Either.new.run
