# frozen_string_literal: true

module DiscourseToMarkdown
  class TopicRenderer
    def initialize(topic, guardian:, post_number: nil)
      @topic = topic
      @guardian = guardian
      @post_number = post_number&.to_i
    end

    def render
      [header, posts_section, footer].compact.join("\n\n") + "\n"
    end

    def visible_posts
      @visible_posts ||=
        begin
          scope = @topic.posts.includes(:user)
          scope =
            if single_post?
              scope.where(post_number: @post_number).limit(1)
            else
              scope.order(:post_number)
            end
          # Delegate to Guardian for the authoritative per-post check so we
          # don't leak whispers, trashed posts, or hidden posts to readers who
          # aren't allowed to see them.
          scope.to_a.select { |post| @guardian.can_see_post?(post) }
        end
    end

    private

    def single_post?
      !@post_number.nil?
    end

    def header
      lines = ["# #{@topic.title}"]

      if SiteSetting.discourse_to_markdown_include_post_metadata
        lines << ""
        lines << "**URL:** #{@topic.url}"
        lines << "**Category:** #{@topic.category.name}" if @topic.category
        lines << "**Tags:** #{@topic.tags.map(&:name).join(", ")}" if @topic.tags.any?
        lines << "**Created:** #{@topic.created_at.iso8601}"
        lines << "**Posts:** #{visible_post_count}"
        lines << "**Showing post:** #{@post_number} of #{visible_post_count}" if single_post?
      end

      lines.join("\n")
    end

    # Use the guardian-appropriate count so whispers (and other staff-only
    # posts) don't leak their existence to anon/regular readers via the
    # metadata header or footer. Mirrors the count Discourse shows on the
    # HTML topic view.
    def visible_post_count
      @guardian.is_staff? ? @topic.highest_staff_post_number : @topic.highest_post_number
    end

    def posts_section
      visible_posts.map { |post| render_post(post) }.join("\n\n---\n\n")
    end

    def render_post(post)
      heading =
        "## Post #{post.post_number} by @#{post.user&.username} — #{post.created_at.iso8601}"
      body = cached_body_for(post)
      "#{heading}\n\n#{body.strip}"
    end

    # Per-post cache keyed on `post.updated_at`, so edits produce a new key
    # automatically — no explicit invalidation needed. `Discourse.cache` is
    # Redis-backed in production and an in-memory store in dev/test.
    def cached_body_for(post)
      cache_key = "dtm:post:#{post.id}:#{post.updated_at.to_i}"
      Discourse
        .cache
        .fetch(cache_key, expires_in: 1.week) { CookedProcessor.to_markdown(post.cooked) }
    end

    def footer
      return "---\n\n_[View the full topic](#{@topic.url})._" if single_post?

      nil
    end
  end
end
