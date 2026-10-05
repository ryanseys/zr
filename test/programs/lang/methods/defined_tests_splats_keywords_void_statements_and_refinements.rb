# defined? tests a splat's value and a call's keywords, gives "expression"
# for parentheses with a `;`, and sees the refinements in use at the site.
class RefinedClass; end
module RefiningModule
  refine RefinedClass do
    def pub; end
    private
    def priv; end
  end
  def self.call_without_using(x = RefinedClass.new) = defined?(x.pub)
  def self.vcall_without_using(x = RefinedClass.new) = x.instance_eval { defined?(priv) }
  using self
  def self.call_with_using(x = RefinedClass.new) = defined?(x.pub)
  def self.vcall_with_using(x = RefinedClass.new) = x.instance_eval { defined?(priv) }
end
def m
  p [defined?([*a]), defined?(itself(*a)), defined?([*itself]), defined?(itself(*itself))]
  p [defined?({a: a}), defined?({a => 1}), defined?({a => a}), defined?({**a})]
  p [defined?(itself(a: a)), defined?(itself(a => 1)), defined?(itself(**a)), defined?(itself({a: a})), defined?(itself({**a}))]
  p [defined?({a: itself}), defined?({itself => 1}), defined?({**itself}), defined?(itself(a: itself)), defined?(itself(**itself)), defined?(itself({a: itself}))]
  p [defined? (;x), defined? (x;), defined? (

    x

  )]
  x = 1
  p [defined? (;x), defined? (x;), defined? (

    x

  )]
end
m
p [RefiningModule.call_without_using, RefiningModule.vcall_without_using, RefiningModule.call_with_using, RefiningModule.vcall_with_using]
# A respond_to? of the program that takes one parameter answers for
# respond_to_missing?, with a warning that the signature is deprecated.
obj = +"x"
class << obj
  def respond_to?(_name) = true
end
Warning[:deprecated] = true
p defined?(obj.foo)
Warning[:deprecated] = false
p defined?(obj.foo)
