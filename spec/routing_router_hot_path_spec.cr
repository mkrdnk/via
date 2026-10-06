require "./spec_helper"

describe Via::Routing::Router do
  it "matches multibyte route prefixes only on path segment boundaries" do
    root = Via::Route.new(nil, "/", URI.parse("http://root"))
    café = Via::Route.new(nil, "/café", URI.parse("http://cafe"))
    router = Via::Router.new([root, café])

    router.match("not a valid authority", "/café/menu").should eq(café)
    router.match("not a valid authority", "/café-menu").should eq(root)
  end

  it "normalizes the authority when a host-specific route can match" do
    fallback = Via::Route.new(nil, "/", URI.parse("http://fallback"))
    hosted = Via::Route.new("api.example.com", "/", URI.parse("http://api"))
    router = Via::Router.new([fallback, hosted])

    router.match("API.Example.COM:8443", "/").should eq(hosted)
  end

  it "matches host-specific routes appended after initialization" do
    fallback = Via::Route.new(nil, "/", URI.parse("http://fallback"))
    routes = [fallback]
    router = Via::Router.new(routes)
    hosted = Via::Route.new("api.example.com", "/", URI.parse("http://api"))
    routes << hosted

    router.match("API.Example.COM:8443", "/").should eq(hosted)
  end
end
