# Ripper#end_seen? is false before a parse, and yydebug keeps the flag
# that yydebug= gives.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: !#{e.class}: #{e.message[0, 100]}"
end

require "ripper"
t("end_seen? unparsed") { Ripper.new("def a; end").end_seen? }
t("end_seen? parsed") { r = Ripper.new("1\n__END__\nx"); r.parse; r.end_seen? }
t("end_seen? no end") { r = Ripper.new("1"); r.parse; r.end_seen? }
t("yydebug") { r = Ripper.new("1"); [r.yydebug, r.yydebug = 1, r.yydebug, (r.yydebug = nil), r.yydebug] }
t("yydebug=") { Ripper.new("1").send(:yydebug=, :x) }
t("ivars") { r = Ripper.new("1"); r.yydebug = true; r.instance_variables.include?(:@yydebug) }
