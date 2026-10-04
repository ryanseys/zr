# A rescue clause whose class autoloads a file that raises and rescues
# inside does not lose the exception being matched.
autoload :EX1, File.join(Dir.pwd, "code", "ex1.rb")
def use_ex1
  begin
    begin
      raise "test exception"
    rescue EX1
    end
  rescue RuntimeError => e
    return [:good, e.message, $!&.message]
  end
end
p use_ex1
begin
  raise ArgumentError, "x"
rescue IndexError, ArgumentError => e
  p e.class
end
p $!
