# A subclass calls a parent `initialize` through `super`. The parent
# body has a String local and an early bare `return` (as in
# `return if x.nil?`). Both calls to `new` work.

class T_initialize_void_wrapper_gc_save_Base
  attr_reader :extra
  def initialize(skip)
    note = "base"
    if skip
      return        # bare `return` from initialize
    end
    @extra = note
  end
end

class T_initialize_void_wrapper_gc_save_Child < T_initialize_void_wrapper_gc_save_Base
  def initialize
    super(false)    # calls the parent's initialize
  end
end

# Keep both T_initialize_void_wrapper_gc_save_Child objects in an Array.
all = [T_initialize_void_wrapper_gc_save_Child.new, T_initialize_void_wrapper_gc_save_Child.new]
puts all.length          # 2
