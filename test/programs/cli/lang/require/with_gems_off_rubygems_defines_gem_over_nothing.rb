# With gems off, ruby has no Kernel#gem and LoadError has no message of
# its own until rubygems loads. A require of rubygems then defines them
# with no warning, as it does at ruby's boot with gems on.
script = <<~'RUBY'
  p respond_to?(:gem, true), LoadError.instance_method(:message).owner
  begin
    gem "minitest"
  rescue NoMethodError => e
    p e.message
  end
  require "rubygems"
  p respond_to?(:gem, true), LoadError.instance_method(:message).owner
RUBY
out = IO.popen([RbConfig.ruby, "-w", "--disable-gems", "-e", script], err: [:child, :out], &:read)
puts out
p $?.exitstatus
