# frozen_string_literal: true

module Ze0
  # Where a local variable lives.
  #
  # `slot` is always a stack slot. `boxed` says the slot holds a pointer to
  # a heap cell rather than the value itself, which is what a name a block
  # captured needs: the cell outlives the frame and every closure over the
  # name shares it. Every read and write goes through `Lower`, which
  # dispatches on this.
  Local = Struct.new(:slot, :boxed) do
    def boxed? = boxed
  end

  # One function being lowered: the CLIF function itself, the bases its
  # code reads, its locals, its `self`, and the blocks every exit path
  # lands in.
  #
  # Scopes nest -- a block body lowers inside the method that wrote it --
  # so `Lower` keeps a stack of these rather than one set of instance
  # variables.
  class Scope
    # `:toplevel` or `:body`; a class body and a block body join them.
    attr_reader :f, :kind, :locals
    # The `self` of the frame, and the caller's slot a value is answered in.
    attr_accessor :self_operand, :out
    # `zeo_rodata` and `zeo_syms`, read once per function.
    attr_accessor :rodata, :syms
    # The shared exits: a raise, a normal finish, and the single block that
    # releases the locals and answers `status`.
    attr_accessor :raise_block, :done_block, :exit_block, :status

    def initialize(f, kind)
      @f = f
      @kind = kind
      @locals = {}
    end
  end
end
