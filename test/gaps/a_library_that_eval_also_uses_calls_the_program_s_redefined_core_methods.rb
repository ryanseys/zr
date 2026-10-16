# In ruby, json's and digest's Ruby code calls the core methods that the
# program redefines. A program that evals shares those libraries with
# eval's compiler, which zr builds as it builds the core library, so
# their own calls go to the core's methods (docs: differences-from-ruby).
eval("1")
require "json"
require "digest"

class Hash
  alias_method :plain_merge!, :merge!
  def merge!(*args, &)
    puts "program merge!"
    plain_merge!(*args, &)
  end
end

class Array
  alias_method :plain_pack, :pack
  def pack(format, **opts) = format == "m0" ? "PATCHED" : plain_pack(format, **opts)
end

p JSON.dump([1], strict: false)
p Digest::SHA256.base64digest("x")
