prev = $counter.increment
eval <<-RUBY
  module Counted#{prev}
    sleep(0.01)
    def self.foo = #{prev}
  end
RUBY
