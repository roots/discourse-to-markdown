# frozen_string_literal: true

module DiscourseToMarkdown
  class MdUrlMiddleware
    ENV_FLAG = "discourse_to_markdown.md_url"
    SUFFIX = ".md"

    def initialize(app)
      @app = app
    end

    def call(env)
      rewrite_md_suffix(env)
      rewrite_homepage_for_markdown(env)

      status, headers, body = @app.call(env)

      headers = headers.merge("X-Robots-Tag" => "noindex, nofollow") if env[ENV_FLAG]

      [status, headers, body]
    end

    private

    def rewrite_md_suffix(env)
      return unless md_urls_enabled? && md_suffixed?(env["PATH_INFO"])

      env["PATH_INFO"] = env["PATH_INFO"].delete_suffix(SUFFIX)
      env[ENV_FLAG] = true
    end

    # Rails' root route uses a HomePageConstraint that doesn't match when
    # Accept asks for Markdown, so `/` would fall through to Rails' default
    # WelcomeController. Rewrite to `/latest` so routing picks up
    # ListController#latest, where our before_action renders Markdown.
    # Mirrors the `/latest.md` alternate URL we already advertise for `/`.
    def rewrite_homepage_for_markdown(env)
      return unless SiteSetting.discourse_to_markdown_enabled
      return unless env["PATH_INFO"] == "/"
      return unless AcceptHeader.prefers_markdown?(env["HTTP_ACCEPT"])

      env["PATH_INFO"] = "/latest"
    end

    def md_urls_enabled?
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
