# frozen_string_literal: true

require "time"

unless defined?(SiteSetting)
  module SiteSetting
    @settings = { discourse_to_markdown_include_post_metadata: true }

    class << self
      def method_missing(name, *args)
        if name.to_s.end_with?("=")
          @settings[name.to_s.chomp("=").to_sym] = args.first
        else
          @settings.fetch(name, true)
        end
      end

      def respond_to_missing?(*)
        true
      end
    end
  end
end

require_relative "../../../lib/discourse_to_markdown/topic_list_renderer"

FakeUser = Struct.new(:username) unless defined?(FakeUser)
FakeTopic = Struct.new(:title, :relative_url, :user, :last_posted_at, :excerpt) unless defined?(
  FakeTopic
)

RSpec.describe DiscourseToMarkdown::TopicListRenderer do
  let(:alice) { FakeUser.new("alice") }
  let(:bob) { FakeUser.new("bob") }
  let(:posted_at) { Time.utc(2026, 4, 21, 12, 0, 0) }

  let(:topics) do
    [
      FakeTopic.new("First topic", "/t/first/1", alice, posted_at, "First excerpt"),
      FakeTopic.new("Second topic", "/t/second/2", bob, posted_at + 3600, "Second excerpt"),
    ]
  end

  def render(**overrides)
    described_class.render(
      topics: overrides.fetch(:topics, topics),
      title: overrides.fetch(:title, "Latest"),
      request_path: overrides.fetch(:request_path, "/latest"),
      page: overrides.fetch(:page, 1),
    )
  end

  describe "header" do
    it "starts with an h1 of the list title" do
      expect(render).to start_with("# Latest\n")
    end

    it "includes URL and topic count when metadata is enabled" do
      out = render
      expect(out).to include("**URL:** /latest")
      expect(out).to include("**Topics on this page:** 2")
    end

    it "notes the current page when not on page 1" do
      out = render(page: 3)
      expect(out).to include("**Page:** 3")
    end

    it "skips metadata when include_post_metadata is disabled" do
      SiteSetting.discourse_to_markdown_include_post_metadata = false
      expect(render).not_to include("**URL:**")
    ensure
      SiteSetting.discourse_to_markdown_include_post_metadata = true
    end
  end

  describe "topic entries" do
    it "renders each topic as a linked h2 with author and last-posted timestamp" do
      out = render
      expect(out).to include("## [First topic](/t/first/1)")
      expect(out).to include("**Author:** @alice")
      expect(out).to include("**Last posted:** 2026-04-21T12:00:00Z")
      expect(out).to include("## [Second topic](/t/second/2)")
      expect(out).to include("**Author:** @bob")
    end

    it "separates topics with ---" do
      expect(render).to include("\n\n---\n\n")
    end

    it "includes the excerpt when present" do
      expect(render).to include("First excerpt")
      expect(render).to include("Second excerpt")
    end

    it "omits the author line when topic has no user" do
      topics_without_author = [FakeTopic.new("Orphan", "/t/orphan/9", nil, posted_at, "x")]
      expect(render(topics: topics_without_author)).not_to include("**Author:**")
    end

    it "omits the excerpt line when blank" do
      topics_without_excerpt = [FakeTopic.new("Title", "/t/x/1", alice, posted_at, "")]
      out = render(topics: topics_without_excerpt)
      expect(out).to end_with("**Last posted:** 2026-04-21T12:00:00Z\n")
    end
  end

  describe "with an empty list" do
    it "still renders the header" do
      out = render(topics: [])
      expect(out).to start_with("# Latest\n")
      expect(out).to include("**Topics on this page:** 0")
    end
  end
end
