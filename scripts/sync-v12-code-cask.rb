#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open-uri"
require "tempfile"

release_path = ARGV.fetch(0)
release = JSON.parse(File.read(release_path))
tag = release.fetch("tag_name")

unless tag.match?(/\Av\d+\.\d+\.\d+\z/)
  warn "Latest release #{tag.inspect} is not a stable semantic version."
  exit 1
end

version = tag.delete_prefix("v")
repository = "12ya/t3code"
assets = release.fetch("assets").to_h { |asset| [asset.fetch("name"), asset] }
arches = { arm: "arm64", intel: "x64" }

checksums = arches.to_h do |homebrew_arch, artifact_arch|
  artifact_name = "V12-#{version}-#{artifact_arch}.dmg"
  asset = assets[artifact_name]
  abort "Release #{tag} is missing #{artifact_name}." unless asset

  published_digest = asset["digest"]
  if published_digest&.match?(/\Asha256:[0-9a-f]{64}\z/)
    next [homebrew_arch, published_digest.delete_prefix("sha256:")]
  end

  Tempfile.create(["v12-code-#{artifact_arch}", ".dmg"]) do |file|
    headers = { "User-Agent" => "12ya-homebrew-tap" }
    token = ENV["GH_TOKEN"]
    headers["Authorization"] = "Bearer #{token}" unless token.nil? || token.empty?

    URI.open(asset.fetch("browser_download_url"), headers) do |download|
      IO.copy_stream(download, file)
    end
    file.flush
    [homebrew_arch, Digest::SHA256.file(file.path).hexdigest]
  end
end

cask = <<~RUBY
  cask "v12-code" do
    arch arm: "arm64", intel: "x64"

    version "#{version}"
    sha256 arm:   "#{checksums.fetch(:arm)}",
           intel: "#{checksums.fetch(:intel)}"

    url "https://github.com/#{repository}/releases/download/v\#{version}/V12-\#{version}-\#{arch}.dmg",
        verified: "github.com/#{repository}/"
    name "V12 Code"
    desc "Minimal GUI for coding agents"
    homepage "https://github.com/#{repository}"

    auto_updates true
    depends_on macos: ">= :monterey"

    app "V12.app"

    zap trash: [
      "~/Library/Application Support/V12",
      "~/Library/Caches/com.v12.v12",
      "~/Library/HTTPStorages/com.v12.v12",
      "~/Library/Preferences/com.v12.v12.plist",
      "~/Library/Saved Application State/com.v12.v12.savedState",
    ]
  end
RUBY

path = File.expand_path("../Casks/v12-code.rb", __dir__)
FileUtils.mkdir_p(File.dirname(path))
File.write(path, cask) unless File.exist?(path) && File.read(path) == cask
puts "Prepared v12-code #{version}."
