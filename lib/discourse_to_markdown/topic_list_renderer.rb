# frozen_string_literal: true

module DiscourseToMarkdown
  class TopicListRenderer
    def self.render(**kwargs)
      new(**kwargs).render
    end

    def initialize(topics:, title:, request_path:, page: 1)
      @topics = topics.to_a
      @title = title
      @request_path = request_path
      @page = [page.to_i, 1].max
    end

    def render
      sections = [header, topics_section].reject { |s| s.nil? || s.empty? }
      sections.join("\n\n") + "\n"
    end

    private

    def header
      lines = ["# #{@title}"]

      if SiteSetting.discourse_to_markdown_include_post_metadata
        lines << ""
        lines << "**URL:** #{@request_path}"
        lines << "**Page:** #{@page}" if @page > 1
        lines << "**Topics on this page:** #{@topics.size}"
      end

      lines.join("\n")
    end

    def topics_section
      @topics.map { |topic| render_topic(topic) }.join("\n\n---\n\n")
    end

    def render_topic(topic)
      lines = ["## [#{topic.title}](#{topic.relative_url})"]

      metadata = []
      metadata << "**Author:** @#{topic.user.username}" if topic.user
      metadata << "**Last posted:** #{topic.last_posted_at.iso8601}" if topic.last_posted_at

      if metadata.any?
        lines << ""
        lines.concat(metadata)
      end

      excerpt = topic.excerpt.to_s.strip
      unless excerpt.empty?
        lines << ""
        lines << excerpt
      end

      lines.join("\n")
    end
  end
end
