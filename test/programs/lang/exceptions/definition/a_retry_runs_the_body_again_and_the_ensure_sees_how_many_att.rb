class Attempt
  def initialize
    @attempts = 0
  end

  def attempts
    @attempts
  end

  def run
    begin
      @attempts += 1
      raise "fail" if @attempts < 3
      puts "succeeded after #{@attempts} attempts"
    rescue
      retry if @attempts < 3
    ensure
      puts "ensure ran, attempts=#{@attempts}"
    end
  end
end
Attempt.new.run

