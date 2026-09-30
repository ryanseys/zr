# `obj.extend(M)` copies M's instance methods onto the object's
# singleton and must keep their visibility marks. A `module_function`
# name is private on the instance side, so
# `obj.extend(MF).public_send(:helper)` must raise, the same as CRuby.
#
# The class-receiver twin is already right: `class C; extend M; end` puts M in
# the singleton chain, where visibility is checked by walking real ancestors.

module MF
  module_function
  def helper = :helped
end

o = Object.new.extend(MF)
begin
  p o.public_send(:helper)
rescue NoMethodError => e
  p [:raised, e.class]
end
p o.send(:helper)
p o.singleton_methods.include?(:helper)
p o.public_methods(false).include?(:helper)
p o.private_methods(false).include?(:helper)
