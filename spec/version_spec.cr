require "./spec_helper"

describe Via do
  it "uses the shard version" do
    shard = YAML.parse(File.read(File.join(__DIR__, "..", "shard.yml")))
    Via::VERSION.should eq(shard["version"].as_s)
  end
end
