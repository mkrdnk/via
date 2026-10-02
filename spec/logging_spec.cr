require "./spec_helper"

private class YieldingLogIO < IO
  def initialize
    @memory = IO::Memory.new
  end

  def read(slice : Bytes) : Int32
    0
  end

  def write(slice : Bytes) : Nil
    midpoint = slice.size // 2
    @memory.write(slice[0, midpoint])
    Fiber.yield
    @memory.write(slice[midpoint, slice.size - midpoint])
  end

  def to_s : String
    @memory.to_s
  end
end

describe Via::Logging::Logger do
  it "writes structured key-value records and escapes strings" do
    output = IO::Memory.new
    logger = Via::Logging::Logger.new(output, config_file: "/etc/via/config.yaml")

    logger.info(
      "request.completed",
      request_id: "abc123",
      status: 200,
      path: "/search?q=\"via\"",
      failure: nil
    )

    line = output.to_s
    line.should match(/\Atime=\d{4}-\d{2}-\d{2}T/)
    line.should contain(" level=info event=request.completed")
    line.should contain(%( config_file="/etc/via/config.yaml"))
    line.should contain(%( request_id="abc123"))
    line.should contain(" status=200")
    line.should contain(%( path="/search?q=\\"via\\""))
    line.should contain(" failure=null")
  end

  it "only writes debug records when debug mode is enabled" do
    quiet_output = IO::Memory.new
    Via::Logging::Logger.new(quiet_output).debug("routing.selected", route: "/")
    quiet_output.to_s.should be_empty

    debug_output = IO::Memory.new
    Via::Logging::Logger.new(debug_output, debug_enabled: true)
      .debug("routing.selected", route: "/")
    debug_output.to_s.should contain("level=debug event=routing.selected")
  end

  it "appends records at or above the configured level to a file" do
    with_temp_directory do |directory|
      path = File.join(directory, "via.log")
      File.write(path, "existing record\n")
      logger = Via::Logging::Logger.new(IO::Memory.new)
      logger.configure(path, Via::Logging::Level::Warn)

      logger.debug("debug.event")
      logger.info("info.event")
      logger.warn("warn.event")
      logger.error("error.event")
      logger.close

      content = File.read(path)
      content.should start_with("existing record\n")
      content.should_not contain("debug.event")
      content.should_not contain("info.event")
      content.should contain("level=warn event=warn.event")
      content.should contain("level=error event=error.event")
    end
  end

  it "keeps the current output when a new log file cannot be opened" do
    with_temp_directory do |directory|
      output = IO::Memory.new
      logger = Via::Logging::Logger.new(output)

      expect_raises(Via::ConfigurationError, "Could not open log_file") do
        logger.configure(directory, Via::Logging::Level::Info)
      end
      logger.error("logging.still_available")

      output.to_s.should contain("event=logging.still_available")
    end
  end

  it "switches the log destination and level during runtime apply" do
    with_temp_directory do |directory|
      first_path = File.join(directory, "first.log")
      second_path = File.join(directory, "second.log")
      fallback = IO::Memory.new
      state = Via::RuntimeState.new(fallback)
      route = Via::Route.new(nil, "/", URI.parse("http://localhost:3000"))

      state.apply(Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 8080),
        [route],
        log_file: first_path,
        log_level: Via::Logging::Level::Info
      ))
      state.apply(
        Via::ValidatedConfig.new(
          Via::ListenAddress.new("127.0.0.1", 8080),
          [route],
          log_file: second_path,
          log_level: Via::Logging::Level::Error
        ),
        reloaded: true
      )
      state.reject("via.yaml", Via::ConfigurationError.new("broken reload"))
      state.close

      File.read(first_path).should contain("event=config.applied")
      second = File.read(second_path)
      second.should_not contain("event=config.reloaded")
      second.should contain("level=error event=config.rejected")
      fallback.to_s.should be_empty
    end
  end

  it "gives a CLI level override priority over debug mode and configuration" do
    with_temp_directory do |directory|
      path = File.join(directory, "via.log")
      state = Via::RuntimeState.new(
        IO::Memory.new,
        debug: true,
        log_level_override: Via::Logging::Level::Error
      )
      config = Via::ValidatedConfig.new(
        Via::ListenAddress.new("127.0.0.1", 8080),
        [Via::Route.new(nil, "/", URI.parse("http://localhost:3000"))],
        log_file: path,
        log_level: Via::Logging::Level::Debug
      )

      state.apply(config, source: "/etc/via/config.yaml")
      state.reject("/etc/via/config.yaml", Via::ConfigurationError.new("broken reload"))
      state.close

      content = File.read(path)
      content.should_not contain("event=config.applied")
      content.should contain("level=error event=config.rejected")
      content.should contain(%(config_file="/etc/via/config.yaml"))
    end
  end

  it "keeps concurrent records on separate lines" do
    output = IO::Memory.new
    logger = Via::Logging::Logger.new(output)
    done = Channel(Nil).new(20)

    20.times do |index|
      spawn do
        logger.info("concurrent.test", index: index)
        done.send(nil)
      end
    end
    20.times { done.receive }

    lines = output.to_s.lines
    lines.size.should eq(20)
    lines.each { |line| line.should contain(" event=concurrent.test ") }
  end

  it "serializes records from separate loggers sharing an output" do
    output = YieldingLogIO.new
    first = Via::Logging::Logger.new(output, config_file: "first.yaml")
    second = Via::Logging::Logger.new(output, config_file: "second.yaml")
    done = Channel(Nil).new(20)

    10.times do |index|
      spawn do
        first.info("shared.test", index: index)
        done.send(nil)
      end
      spawn do
        second.info("shared.test", index: index)
        done.send(nil)
      end
    end
    20.times { done.receive }

    lines = output.to_s.lines
    lines.size.should eq(20)
    lines.each do |line|
      line.should match(/\Atime=.* event=shared\.test config_file="(?:first|second)\.yaml" index=\d+\z/)
    end
  end

  it "records request completion without leaking query parameters" do
    upstream = HTTP::Server.new { |context| context.response << "ok" }

    with_server(upstream) do |upstream_address|
      log = IO::Memory.new
      config = Via::Configuration::Validated.new(
        Via::Configuration::ListenAddress.new("127.0.0.1", 0),
        [
          Via::Routing::Route.new(
            nil,
            "/",
            URI.parse("http://#{upstream_address}")
          ),
        ]
      )
      state = Via::RuntimeState.new(log)
      state.apply(config, source: "/etc/via/config.yaml")
      server = Via::Server.new(config.listen, state)
      address = server.bind
      spawn server.listen

      begin
        HTTP::Client.get("http://#{address}/items?token=secret")
        records = log.to_s
        records.should contain("event=request.completed")
        records.should contain(%(config_file="/etc/via/config.yaml"))
        records.should contain(%(path="/items"))
        records.should_not contain("token=secret")
        records.should contain("status=200")
        records.should match(/duration_ms=\d/)
      ensure
        server.close
      end
    end
  end
end
