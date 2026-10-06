require "open3"

# Which commit is running, and when it was made, for the page footer.
# The production image has no .git (see .dockerignore), so there it comes
# from the environment: Kamal sets KAMAL_VERSION (the commit SHA) on every
# deploy, and config/deploy.yml sets GIT_COMMIT_TIMESTAMP. In development,
# git itself answers.
class AppVersion
  REPOSITORY_URL = "https://github.com/bovender/keila-contact-manager".freeze

  def self.commit_sha
    ENV["KAMAL_VERSION"].presence || git("rev-parse", "HEAD")
  end

  def self.short_sha
    commit_sha&.first(7)
  end

  def self.commit_time
    raw = ENV["GIT_COMMIT_TIMESTAMP"].presence || git("log", "-1", "--format=%cI")
    Time.iso8601(raw) if raw.present?
  rescue ArgumentError
    nil
  end

  def self.commit_url
    "#{REPOSITORY_URL}/commit/#{commit_sha}" if commit_sha
  end

  def self.git(*args)
    return unless File.directory?(Rails.root.join(".git"))

    stdout, status = Open3.capture2("git", "-C", Rails.root.to_s, *args)
    stdout.strip.presence if status.success?
  end
  private_class_method :git
end
