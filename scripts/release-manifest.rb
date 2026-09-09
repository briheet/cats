require 'json'
require 'digest'
require 'base64'

tag, repository, team, directory = ARGV
abort 'Expected tag, owner/repository, team ID, and archive directory' unless
  tag&.match?(/\Av\d+\.\d+\.\d+\z/) && repository&.match?(/\A[\w.-]+\/[\w.-]+\z/) && team&.match?(/\A[A-Z0-9]{10}\z/) && directory
manifest = { 'aarch64-darwin' => 'arm64', 'x86_64-darwin' => 'x86_64' }.transform_values do |arch|
  name = "Cats-#{arch}.zip"
  {
    version: tag.delete_prefix('v'),
    url: "https://github.com/#{repository}/releases/download/#{tag}/#{name}",
    hash: "sha256-#{Base64.strict_encode64(Digest::SHA256.file(File.join(directory, name)).digest)}",
    appGroup: "#{team}.dev.cats.shared"
  }
end
puts JSON.pretty_generate(manifest)
