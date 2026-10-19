# ruby finds the files of its library only through $LOAD_PATH. Once the
# program takes the library's directory off, a require of one fails,
# also of one that has loaded, by a literal name or a computed one. With
# the directory back, they load again. Gems are off: with gems, rubygems
# itself loads files of the library as it searches.
script = <<~'RUBY'
  require "shellwords"
  saved = $LOAD_PATH.dup
  $LOAD_PATH.clear
  name = "English"
  [-> { require "shellwords" }, -> { require "English" }, -> { require name }].each do |required|
    p required.call
  rescue LoadError => e
    p [e.class, e.message, e.path]
  end
  $LOAD_PATH.replace(saved)
  p require("English"), require(name), require("shellwords")
RUBY
out = IO.popen([RbConfig.ruby, "--disable-gems", "-e", script], err: [:child, :out], &:read)
puts out
p $?.exitstatus
