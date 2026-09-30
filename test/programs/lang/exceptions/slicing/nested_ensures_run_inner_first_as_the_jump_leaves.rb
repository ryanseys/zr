def d
  begin
    begin
      return 5
    ensure
      puts "inner d"
    end
  ensure
    puts "outer d"
  end
end
p d

