# A top-level const assigned via `<CONST> = <Class>.new(...)` is not
# yet defined while the right side runs. So when initialize (or any
# method that it calls) reads <CONST>, the read raises NameError, as
# in MRI.

class App
  def initialize
    @arr = []
    @arr << 1   # force heap allocation so App is not value-type
    begin
      _ = APP
      puts "direct: no raise"
    rescue NameError => e
      puts "direct: " + e.message
    end
    helper
  end

  def helper
    begin
      _ = APP
      puts "indirect: no raise"
    rescue NameError => e
      puts "indirect: " + e.message
    end
  end
end

APP = App.new
puts "after: APP class = " + APP.class.name
