# frozen_string_literal: true

module DiscourseToMarkdown
  class MdUrlMiddleware
    ENV_FLAG = "discourse_to_markdown.md_url"
    SUFFIX = ".md"

    def initialize(app)
      @app = app
    end

    def call(env)
      rewrite = enabled? && md_suffixed?(env["PATH_INFO"])

      if rewrite
        env["PATH_INFO"] = env["PATH_INFO"].delete_suffix(SUFFIX)
        env[ENV_FLAG] = true
      end

      status, headers, body = @app.call(env)

      headers = headers.merge("X-Robots-Tag" => "noindex, nofollow") if env[ENV_FLAG]

      [status, headers, body]
    end

    private

    def enabled?
      SiteSetting.discourse_to_markdown_enabled && SiteSetting.discourse_to_markdown_md_urls_enabled
    end

    # Accept `/latest.md`, `/t/foo/5.md`, etc. Reject `/.md` and `/foo/.md` —
    # the last path segment must have content before the suffix.
    def md_suffixed?(path)
      return false unless path&.end_with?(SUFFIX)

      path.split("/").last.to_s.length > SUFFIX.length
    end
  end
end
