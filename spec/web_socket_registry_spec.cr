require "./spec_helper"

describe Via::Runtime::WebSocketRegistry do
  it "tracks reservations independently even when they share an upstream" do
    registry = Via::Runtime::WebSocketRegistry.new
    upstream = IO::Memory.new
    first = registry.reserve(upstream)
    second = registry.reserve(upstream)
    released_downstream = IO::Memory.new
    active_downstream = IO::Memory.new

    registry.release(first)
    registry.release(first)
    registry.attach(first, released_downstream).should be_false
    released_downstream.closed?.should be_true
    registry.attach(second, active_downstream).should be_true
    upstream.closed?.should be_false

    registry.close
    upstream.closed?.should be_true
    active_downstream.closed?.should be_true
  end

  it "does not close transports belonging to released entries" do
    registry = Via::Runtime::WebSocketRegistry.new
    upstream = IO::Memory.new
    downstream = IO::Memory.new
    entry = registry.reserve(upstream)
    registry.attach(entry, downstream).should be_true

    registry.release(entry)
    registry.close
    upstream.closed?.should be_false
    downstream.closed?.should be_false
  end

  it "rejects entries from another registry" do
    registry = Via::Runtime::WebSocketRegistry.new
    other = Via::Runtime::WebSocketRegistry.new
    upstream = IO::Memory.new
    downstream = IO::Memory.new
    entry = other.reserve(upstream)

    registry.attach(entry, downstream).should be_false
    downstream.closed?.should be_true
    registry.release(entry)
    registry.close
    upstream.closed?.should be_false
    other.close
    upstream.closed?.should be_true
  end

  it "closes reservations and attachments made after shutdown" do
    registry = Via::Runtime::WebSocketRegistry.new
    registry.close
    registry.close
    upstream = IO::Memory.new
    downstream = IO::Memory.new

    entry = registry.reserve(upstream)
    upstream.closed?.should be_true
    registry.attach(entry, downstream).should be_false
    downstream.closed?.should be_true
    registry.release(entry)
    registry.drain(1.second)
  end

  it "forces active transports closed when the drain deadline expires" do
    registry = Via::Runtime::WebSocketRegistry.new
    upstream = IO::Memory.new
    downstream = IO::Memory.new
    entry = registry.reserve(upstream)
    registry.attach(entry, downstream).should be_true

    registry.drain(Time::Span.zero)
    upstream.closed?.should be_true
    downstream.closed?.should be_true
    registry.release(entry)
  end
end
