# With gems off, no ErrorHighlight autoload is set up, and with
# error_highlight off, none is loaded: an eval still runs, and an error
# in it shows no highlight. With both on, the error shows its highlight.
script = <<~'RUBY'
  p defined?(ErrorHighlight)
  p eval("1 + 2")
  Class.new.module_eval("def x = 3")
  p Ripper.sexp("a") if require "ripper"
  begin
    eval("nil.upcase")
  rescue NoMethodError => e
    puts e.detailed_message(highlight: false)
  end
  begin
    instance_eval("[1].fetch(5)", "f.rb")
  rescue IndexError => e
    puts e.detailed_message(highlight: false)
  end
  require "tmpdir"
  Dir.mktmpdir do |dir|
    File.write("#{dir}/x.rb", "nil.upcase\n")
    load "#{dir}/x.rb"
  rescue NoMethodError => e
    puts e.detailed_message(highlight: false)
  end
  p defined?(ErrorHighlight)
RUBY

[[], ["--disable-gems"], ["--disable-error_highlight"], ["--disable-gems", "--enable-error_highlight"]].each do |options|
  puts "== #{options.join(" ")}"
  out = IO.popen([RbConfig.ruby, *options, "-e", script], err: [:child, :out], &:read)
  puts out
  p $?.exitstatus
end
