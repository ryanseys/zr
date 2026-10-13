# An autoload that a box registers loads its feature through the box's
# own `require`, which the box may decorate (Kernel.prepend in the box),
# wherever the constant is first read: from main or from the box. An
# autoload that main registers uses main's require.
box = Ruby::Box.new
box.eval(<<~RUBY)
  FEATURE = "/nonexistent/box_virtual_feature"
  SECOND = "/nonexistent/box_second_feature"
  module BoxDecor
    def require(path)
      if path == FEATURE || path == SECOND
        Holder.const_set(path == FEATURE ? :Virtual : :Second, "decorated in \#{Ruby::Box.current.inspect[/user/]}")
        return true
      end
      super
    end
  end
  Kernel.prepend(BoxDecor)
  module Holder
    autoload :Virtual, FEATURE
    autoload :Second, SECOND
  end
RUBY
p box::Holder::Virtual
p box.eval("Holder::Second")
module MainHolder
  autoload :Missing, "/nonexistent/main_feature"
end
begin
  MainHolder::Missing
rescue LoadError => e
  p [e.class, e.message]
end
