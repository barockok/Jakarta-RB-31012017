# $stdout.sync = true
require 'logger'
class Daemon

  attr_reader :logger, :process_thread, :pidfile, :logfile

  def initialize(stop_timeout: 30, watch_process: false, logfile:, pidfile: )
    @logfile = logfile
    @pidfile = pidfile
    @stop_timeout = stop_timeout
    @watch_process = watch_process
  end

  def process
    @process = proc { yield }
    self
  end

  def on_interrupt
    @on_interrupt = proc{ yield }
    self
  end

  def run
    daemonize
    write_pid

    start_main_process
  end

  def start
    if !@process || !@on_interrupt
      puts "Process & interrupt callback should be defined"
      exit(1)
    end

    run
  end


  private
  def daemonize
    ::Process.daemon(true, true)

    [$stdout, $stderr].each do |io|
      File.open(logfile, 'ab') do |f|
        io.reopen(f)
      end
      io.sync = true
    end

    $stdin.reopen('/dev/null')
    initialize_loggger
  end

  def initialize_loggger
    @logger = Logger.new logfile
    @logger.level = Logger::DEBUG
  end

  def write_pid
    if path = pidfile
      pidfile = File.expand_path(path)
      File.open(pidfile, 'w') do |f|
        f.puts ::Process.pid
      end
    end
  end

  def start_main_process
    begin
      signal_pipe = []

      %w{INT TERM USR1 USR2 TTIN HUP}.each do |signal|
        begin
          trap signal do
            signal_pipe << signal
          end
        rescue ArgumentError
          puts "Signal #{signal} not supported"
        end
      end

      @process_thread = safe_thread { @process.call }
      while true
        if readable_signal = signal_pipe.shift
          signal = readable_signal.strip
          handle_signal(signal)
        end

        watch_process_thread
      end
    rescue Interrupt
      stop
      exit(0)
    end
  end

  def safe_thread
    Thread.new do
      begin
        yield
        true
      rescue Interrupt
        stop
        false
      rescue => e
        tag = "[PROCESS ERROR] ".freeze
        logger.error tag + e.class.to_s
        logger.error tag + e.message
        logger.error tag + e.backtrace.join("\n")
        false
      end
    end
  end

  def stop
    @on_interrupt.call
    wait_process_to_complete
    File.delete "#{File.expand_path pidfile}"
  end

  def watch_process_thread
    return unless @watch_process
    thread_alive = @process_thread.alive?
    return if thread_alive

    thread_value = @process_thread.value

    if thread_value == true
      exit(0)
    else
      exit(1)
    end
  end

  def handle_signal signal_code
    print "\n"
    logger.debug "Receiving #{signal_code} signal"
    case signal_code
    when 'INT', 'TERM'
      raise Interrupt
    when 'USR1'
      logger.info "Receives USR1, stop consuming event"
    when 'USR2'
      logger.info "Receives USR2, reopening log file"
      # NOTE: send to logger to reopen the log file
    when 'TTIN'
      logger.info "Receives TTIN, inspecting consumer thread"
      # NOTE trigger poll manager to inspect current state of each consumer thread
    when 'HUP'
      logger.info "Receives HUP, reloading configuration"
      # NOTE: reload configuration
    end
  end

  def wait_process_to_complete
    start_time            = Time.now
    sleep_range           = 0.0..1.5
    last_wait             = 0
    wait_output_threshold = 5.0

    if @stop_timeout
      while (current_wait = Time.now - start_time) < @stop_timeout
        sleep rand(sleep_range)

        if last_wait < (current_wait / wait_output_threshold).round
          logger.info "waiting process to stop"
          last_wait += 1
        end

        break unless @process_thread.alive?
      end
    else

      while true
        current_wait = Time.now - start_time
        sleep rand(sleep_range)
        if last_wait < (current_wait / wait_output_threshold).round
          logger.info "waiting process to stop"
          last_wait += 1
        end

        break unless @process_thread.alive?
      end

    end

    print "\n"
    if @process_thread.alive?
      logger.warn "Process still alive, Shutdown maybe not Gracefully"
    else
      logger.info "Gracefully shutdown"
    end
  end

end