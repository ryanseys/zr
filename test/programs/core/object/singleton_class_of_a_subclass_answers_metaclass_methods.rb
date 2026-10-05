class C
  class << self
    class << self
      def ham = "iberico"
    end
  end
end
class D < C; end
p D.singleton_class.ham
p D.singleton_class.singleton_class.superclass == C.singleton_class.singleton_class
def sw
  eval "class << self\n yield\n end"
end
begin
  sw { 1 }
rescue SyntaxError => e
  p e.class
end
