# A local of one method does not reach the enclosing scope or other
# methods. Two methods that each define `path = ...` with values of
# different types keep their own `path`, and a call with one of them
# passes a String.
#
# Real-world repro shape (after roundhouse-style boil-down):
#
#   module CgiIo
#     def self.parse_request(env, stdin)
#       path = env["PATH_INFO"] || "/"   # path local : nullable-via-||
#       { path: path }
#     end
#   end
#
#   module Db
#     def self.configure(path); ...; end  # path : should be string
#   end
#
#   module Main
#     def self.run_setup
#       path = "/tmp/db"
#       Db.configure(path)               # this call's arg is a String
#     end
#   end

module CgiIo
  def self.parse_request(env)
    path = env["PATH_INFO"] || "/"
    { path: path }
  end
end

module Db
  def self.configure(path)
    "opening " + path
  end
end

module Main
  def self.run_setup
    db_path = "/tmp/db"
    path = (!db_path.nil? && !db_path.empty?) ? db_path : ":memory:"
    Db.configure(path)
  end
end

puts CgiIo.parse_request({ "PATH_INFO" => "/articles" })[:path]
puts Main.run_setup
