# frozen_string_literal: true

# `Sends` for refinements: the `using` rows of a site, and their
# activation around a send.

module Zr
  class Lower
    class Function
      module Sends
        # @type instance: Function

        private

        # `using mod` fills its activation entry, so every send under it
        # sees this module's refinements. It returns its self.
        def using_row(node)
          at_node(node)
          checked(kernel("zr_using_activate", imm(node.id), expr(node.value), imm(node.from)))
          @self
        end

        # Gives the task the refinements that are active at this call, so
        # the lookup sees them. A callee that does a lookup also sees them,
        # as `send`, `respond_to?` and `&:name` do in ruby, on every path
        # of the site. A `using` entry is one element of the activation
        # table, read here inline. The kernel is called only for an entry
        # that is not made yet, for one that forwards to the entry before
        # it (a `using` that a condition skipped), and in a `refine` block,
        # where the list is the owner's and has no entry number.
        def activate(node)
          return if node.using.nil?
          return kernel("zr_activate_owner", @rec) if owner_using?(node)

          rows = global("G_ACTIVATIONS")
          ask = @f.label
          read = @f.label
          have = @f.label
          merge = @f.label
          array = @l.layout("RArray")
          @f.brif(@f.band(@f.icmp("eq", @f.band(rows, imm(7)), imm(0)), @f.icmp("ugt", rows, @qnil)), read, ask)
          switch(read)
          made = @f.icmp("slt", imm(node.using), @f.fetch("i64", rows, off(array, "len")))
          @f.brif(made, have, ask)
          switch(have)
          row = @f.fetch("i64", @f.fetch("i64", rows, off(array, "ptr")), 8 * node.using)
          plain = @f.label
          @f.brif(@f.icmp("eq", @f.band(row, imm(1)), imm(0)), plain, ask)
          switch(plain)
          @f.store(row, @task_addr, off(@task, "refine"), region: :task)
          @f.jump(merge, [])
          switch(ask)
          kernel("zr_activate", imm(node.using))
          @f.jump(merge, [])
          switch(merge)
        end

        # Removes this send's refinements from the task after the send. A
        # kernel callee leaves the word unchanged, and the next plain site
        # must not read it as its own.
        def deactivate(node)
          return if node.using.nil?

          @f.store(@qnil, @task_addr, off(@task, "refine"), region: :task)
        end

        # Whether the site is in a `refine` block. Its list is the owner's,
        # which the kernel reads at each send.
        def owner_using?(node)
          node.using == :owner
        end
      end
    end
  end
end
