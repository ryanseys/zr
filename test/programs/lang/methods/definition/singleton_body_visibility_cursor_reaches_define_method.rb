# A `private` in a `class << self` body is a CURSOR that persists across a
# block: methods `define_method` installs after it are PRIVATE singleton
# methods. Oracle-verified -- `Vis.hidden` raises NoMethodError.
class Vis
  class << self
    private
    [:hidden].each { |n| define_method(n) { :h } }
    public
    [:shown].each { |n| define_method(n) { :s } }
  end
end
p Vis.singleton_class.private_method_defined?(:hidden)
p Vis.singleton_class.public_method_defined?(:shown)
p (Vis.hidden rescue $!.class)
p Vis.shown
