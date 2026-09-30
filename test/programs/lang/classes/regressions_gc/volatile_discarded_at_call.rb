# A top-level begin/rescue around a call that passes a top-level
# local Hash. The call reads the Hash and returns its value.

class T_volatile_discarded_at_call_M
  def self.read(env)
    env["k"]
  end
end

env = { "k" => "v" }
begin
  puts T_volatile_discarded_at_call_M.read(env)
rescue
  puts "rescued"
end
