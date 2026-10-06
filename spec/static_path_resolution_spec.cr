require "./spec_helper"

describe Via::Static::Path do
  it "resolves files inside the root and rejects missing and escaping paths" do
    with_temp_directory do |directory|
      root = File.join(directory, "public")
      FileUtils.mkdir_p(root)
      asset = File.join(root, "asset.txt")
      secret = File.join(directory, "secret.txt")
      File.write(asset, "asset")
      File.write(secret, "secret")
      File.symlink(secret, File.join(root, "escape.txt"))
      File.symlink(File.join(root, "missing.txt"), File.join(root, "broken.txt"))

      resolved = Via::Static::Path.resolve(File.realpath(root), "asset.txt")

      resolved.should_not be_nil
      resolved.not_nil![0].should eq(File.realpath(asset))
      resolved.not_nil![1].file?.should be_true
      Via::Static::Path.resolve(File.realpath(root), "missing.txt").should be_nil
      Via::Static::Path.resolve(File.realpath(root), "broken.txt").should be_nil
      Via::Static::Path.resolve(File.realpath(root), "escape.txt").should be_nil
    end
  end
end
