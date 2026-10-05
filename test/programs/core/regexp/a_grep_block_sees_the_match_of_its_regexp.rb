# grep with a Regexp and a block: the block sees the match in $~, as the
# Regexp#=== that grep sends sets it for grep's caller.
klass = Class.new do
  include Enumerable
  def each
    %w[bar baz].each { |e| yield e }
  end
end
svars = []
klass.new.grep(/(b.)/) { svars << $1 }
p svars
p %w[ab cd].grep(/(c)/) { $1 }, $~ && $~[0]
"xyz" =~ /y/
p [:q].grep(/q/), $~[0]
