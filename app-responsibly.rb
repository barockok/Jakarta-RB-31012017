module MyApp
  extend self

  def start
    # do long process
    @run = true
    while @run do
      sleep 1
      puts Time.now.to_i
    end
  end

  def on_interrupt
    # do other things before quit
    send_intterupt_to_slack
    stop
    # stop the process
  end

  def stop
    @run = false
  end

  def send_intterupt_to_slack
    system %{curl https://slack.com/api/chat.postMessage -X POST \
      -d "channel=@barock19" \
      -d "as_user=true" \
      -d "token=xoxb-128577930231-JfgZOMbvyattkuiJmGJMiGOP" \
      -d "text=MyApp Will Quit"}
  end
end

