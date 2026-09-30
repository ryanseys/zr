def c
  [10, 20].each do |x|
    begin
      return x if x == 20
      puts "seen #{x}"
    ensure
      puts "ensure c #{x}"
    end
  end
  :none
end
p c

