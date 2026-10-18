# Refinement#import_methods takes at least one module.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

r = []
Module.new do
  refine Integer do
    r << (import_methods rescue [$!.class, $!.message])
    r << import_methods(Module.new).class
    r << import_methods(Module.new, Module.new).class
    r << (import_methods(Object) rescue [$!.class, $!.message])
  end
end
t("results") { r }
