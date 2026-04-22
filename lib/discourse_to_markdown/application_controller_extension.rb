# frozen_string_literal: true

module DiscourseToMarkdown
  module ApplicationControllerExtension
    extend ActiveSupport::Concern

    included { before_action :resolve_markdown_preference }

    # Maps the current request path to its absolute Markdown-alternate URL.
    # The home route `/` becomes `/latest.md` (the middleware rejects `/.md`
    # because there's no content segment before the suffix); other paths get
    # `.md` appended after trimming any trailing slash. Absolute URLs match
    # Discourse's own `<link rel="canonical">` convention and stay
    # unambiguous when crawlers, feed readers, or LLMs consume the link
    # out-of-context.
    def markdown_alternate_url_for(path = request.path)
      relative = path == "/" ? "/latest.md" : "#{path.chomp("/")}.md"
      "#{Discourse.base_url}#{relative}"
    end

    private

    def resolve_markdown_preference
      return unless SiteSetting.discourse_to_markdown_enabled

      via_url = request.env[MdUrlMiddleware::ENV_FLAG]
      via_accept = AcceptHeader.prefers_markdown?(request.headers["Accept"])

      return unless via_url || via_accept

      request.formats = %i[md html]
    end

    # Invoked as a before_action by patched controllers that advertise a
    # Markdown sibling. Skips when strict_accept is off, when the URL was
    # the signal (.md suffix), or when the Accept header already allows
    # text/html or text/markdown.
    def enforce_acceptable_representation
      return unless SiteSetting.discourse_to_markdown_enabled
      return unless SiteSetting.discourse_to_markdown_strict_accept
      return if request.env[MdUrlMiddleware::ENV_FLAG]

      accept = request.headers["Accept"]
      return if accept.nil? || accept.strip.empty?

      return if AcceptHeader.quality(accept, "text", "html").positive?
      return if AcceptHeader.quality(accept, "text", "markdown").positive?

      ensure_vary_accept
      render plain: "Available representations: text/html, text/markdown\n",
             status: :not_acceptable,
             content_type: "text/plain"
    end

    # Invoked as an after_action by patched controllers that advertise a
    # Markdown sibling. Appends `Link: <path.md>; rel="alternate";
    # type="text/markdown"` to HTML responses, merging with any existing
    # Link header.
    def advertise_markdown_alternate_link
      return unless SiteSetting.discourse_to_markdown_enabled
      return unless response.media_type == "text/html"

      link = %(<#{markdown_alternate_url_for}>; rel="alternate"; type="text/markdown")
      existing = response.headers["Link"]
      response.headers["Link"] = existing ? "#{existing}, #{link}" : link
    end

    # Renders the given Markdown body and ensures `Vary: Accept` is set so
    # caches don't cross-serve HTML and Markdown representations. Call from
    # the patched controllers instead of `render plain: ..., content_type:`
    # directly — this wraps both concerns in one place.
    def render_markdown(body)
      ensure_vary_accept
      render plain: body, content_type: "text/markdown"
    end

    # Append `Accept` to the Vary header, idempotently and gated on the
    # `discourse_to_markdown_emit_vary` site setting — admins running a
    # reverse proxy that manages Vary themselves can opt out.
    def ensure_vary_accept
      return unless SiteSetting.discourse_to_markdown_emit_vary
      return if response.headers["Vary"].to_s.include?("Accept")

      existing = response.headers["Vary"].to_s
      response.headers["Vary"] = existing.empty? ? "Accept" : "#{existing}, Accept"
    end
  end
end
