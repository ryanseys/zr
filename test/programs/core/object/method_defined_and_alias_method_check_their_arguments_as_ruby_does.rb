# method_defined? and its public, private and protected forms take one
# or two arguments. alias_method converts the old name before the new
# one, so a bad old name is the one the error names.
def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

class Sample
  def pub = 1

  private def priv = 2

  protected def prot = 3
end

%i[method_defined? public_method_defined? private_method_defined? protected_method_defined?].each do |m|
  try("#{m}()") { Sample.send(m) }
  try("#{m}(:pub)") { Sample.send(m, :pub) }
  try("#{m}(:priv)") { Sample.send(m, :priv) }
  try("#{m}(:prot)") { Sample.send(m, "prot") }
  try("#{m}(:to_s, false)") { Sample.send(m, :to_s, false) }
  try("#{m}(:to_s, true)") { Sample.send(m, :to_s, true) }
  try("#{m}(1, 2, 3)") { Sample.send(m, :pub, true, 3) }
  try("#{m}(1)") { Sample.send(m, 1) }
end
try("alias_method(1, 2)") { Sample.send(:alias_method, 1, 2) }
try("alias_method(1, :pub)") { Sample.send(:alias_method, 1, :pub) }
try("alias_method(:x, 2)") { Sample.send(:alias_method, :x, 2) }
try("alias_method(:x, :none)") { Sample.send(:alias_method, :x, :none) }
try("alias_method(:x, :pub)") { Sample.send(:alias_method, :x, :pub) }
try("alias_method(nil, nil)") { Sample.send(:alias_method, nil, nil) }
try("x") { Sample.new.x }
