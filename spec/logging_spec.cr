require "./spec_helper"

describe Via::Logging::Logger do
  it "writes structured key-value records and escapes strings" do
    output = IO::Memory.new
    logger = Via::Logging::Logger.new(output)

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
      server = Via::Server.new(config, log)
      address = server.bind
      spawn server.listen

      begin
        HTTP::Client.get("http://#{address}/items?token=secret")
        records = log.to_s
        records.should contain("event=request.completed")
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
