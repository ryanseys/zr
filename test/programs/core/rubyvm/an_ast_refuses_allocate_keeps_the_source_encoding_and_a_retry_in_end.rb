begin
  RubyVM::AbstractSyntaxTree::Node.allocate
  puts "no error"
rescue TypeError => e
  puts "TypeError: #{e.message}"
end
code = "__ENCODING__".encode(Encoding::EUC_JP)
p eval(code)
p RubyVM::AbstractSyntaxTree.parse(code, keep_script_lines: false).children[2].children[0]
p RubyVM::AbstractSyntaxTree.parse(code, keep_script_lines: true).children[2].children[0]
["END {retry}", "begin rescue; END {retry}; end", "begin rescue; retry; end"].each do |src|
  RubyVM::AbstractSyntaxTree.parse(src)
  puts "ok: #{src}"
rescue SyntaxError => e
  puts "SyntaxError: #{src} #{e.message[/Invalid retry[^\n]*/]}"
end
begin
  RubyVM::AbstractSyntaxTree::Location.allocate
rescue TypeError => e
  puts "TypeError: #{e.message}"
end
begin
  RubyVM::AbstractSyntaxTree.parse("x = 1\nbegin rescue; END {retry}; end")
rescue SyntaxError => e
  p e.message
end
["nil rescue retry", "begin rescue; ensure; p defined?(retry); end", "END { begin; rescue; retry; end }"].each do |src|
  RubyVM::AbstractSyntaxTree.parse(src)
  puts "ok: #{src}"
rescue SyntaxError => e
  puts "SyntaxError: #{src}"
end
p RubyVM::AbstractSyntaxTree.parse("1 + 2").type
