# A `return` written inside an eval'd string belongs to the method the eval
# sits in, not to the eval. The method arms a catch for a return signal that
# carries no home of its own, and it must arm it for every spelling of eval,
# not only for a call written `eval`.

class Widget; end

def literal;      eval("return 1");                :fell_through; end
def instance;     instance_eval("return 2");       :fell_through; end
def on_a_number;  1.instance_eval("return 3");     :fell_through; end
def klass;        Widget.class_eval("return 4");   :fell_through; end
def mod;          Widget.module_eval("return 5");  :fell_through; end
def sent;         send(:eval, "return 6");         :fell_through; end
def sent_twice;   __send__(:eval, "return 7");     :fell_through; end
def fetched;      method(:eval).call("return 8");  :fell_through; end
def bound;        binding.eval("return 9");        :fell_through; end

p [literal, instance, on_a_number, klass, mod, sent, sent_twice, fetched, bound]
