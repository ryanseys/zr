def f
  begin
    yield
    return :after
  ensure
    puts "ensure f"
  end
end
p(f { 1 })
puts "===";
r = [1,2,3].map do |x|
  begin
    next x * 10 if x == 2
    x
  ensure
    puts "ens #{x}"
  end
end
p r
r2 = [1,2,3].each do |x|
  begin
    break :stop if x == 2
  ensure
    puts "b ens #{x}"
  end
end
p r2
tries = 0
r3 = [1,2].map do |x|
  begin
    tries += 1
    redo if x == 1 && tries == 1
    x
  ensure
    puts "r ens #{x} #{tries}"
  end
end
p r3
def deep
  [1,2].each do |x|
    begin
      begin
        next if x == 1
        return :from_block
      ensure
        puts "inner #{x}"
      end
    ensure
      puts "outer #{x}"
    end
  end
  :none
end
p deep
r = [1,2,3].map do |x|
  begin
    next x * 10 if x == 2
    x
  ensure
    puts "ens #{x}"
  end
end
p r
r2 = [1,2,3].each do |x|
  begin
    break :stop if x == 2
  ensure
    puts "b ens #{x}"
  end
end
p r2
