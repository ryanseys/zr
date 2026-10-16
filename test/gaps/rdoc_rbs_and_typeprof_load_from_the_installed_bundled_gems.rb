# ruby loads rdoc, rbs and typeprof from the bundled gems it installs.
# A zr build does not find them yet (the boot and gems work, W14).
def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

t(:rdoc) { require "rdoc"; RDoc::Markup::ToHtml.new(RDoc::Options.new).convert("= Head\n\n*bold* _em_ +code+") }
t(:rbs) { require "rbs"; RBS::Parser.parse_type("Array[Integer | String]").to_s }
t(:typeprof) { require "typeprof"; TypeProf.class rescue $!.class }
