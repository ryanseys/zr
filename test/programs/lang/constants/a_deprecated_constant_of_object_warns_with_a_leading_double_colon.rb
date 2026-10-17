# rb_const_warn_if_deprecated names a constant of Object `::Name`, and
# one of any other module `Mod::Name` (irb's ::RubyLex warns so).
Warning[:deprecated] = true
module Warning
  def self.warn(message, category: nil, **) = $stdout.print("#{category.inspect} #{message}")
end

Old = 1
Object.deprecate_constant :Old
module Box
  Inner = 2
  deprecate_constant :Inner
  def self.read = Old
end

p Old, ::Old, Object::Old, Object.const_get(:Old), Box.read
p defined?(Old), Box::Inner, Box.const_get(:Inner)
class Object
  p Old
end
Warning[:deprecated] = false
p Old
