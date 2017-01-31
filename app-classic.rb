module MyApp
  extend self
  def start
    # do long process
    loop do
      sleep 1
      puts Time.now.to_i
    end
  end
end


MyApp.start