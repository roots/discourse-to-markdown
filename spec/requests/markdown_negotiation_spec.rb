# frozen_string_literal: true

RSpec.describe "Markdown negotiation" do
  before { enable_current_plugin }

  fab!(:category)
  fab!(:user)
  fab!(:topic) do
    Fabricate(:topic, user: user, category: category, title: "Hello from the integration suite")
  end
  fab!(:first_post) do
    Fabricate(:post, topic: topic, user: user, raw: "Welcome to the forum.", post_number: 1)
  end

  describe "topic route" do
    describe "with Accept: text/markdown" do
      before { get "/t/#{topic.slug}/#{topic.id}", headers: { "Accept" => "text/markdown" } }

      it "returns a Markdown representation" do
        expect(response.status).to eq(200)
        expect(response.media_type).to eq("text/markdown")
        expect(response.body).to include("# #{topic.title}")
        expect(response.body).to include("@#{user.username}")
        expect(response.body).to include("Welcome to the forum.")
      end

      it "includes Vary: Accept so caches don't cross-serve" do
        expect(response.headers["Vary"].to_s).to include("Accept")
      end

      it "does not set X-Robots-Tag (request came in on the canonical URL)" do
        expect(response.headers["X-Robots-Tag"]).to be_nil
      end
    end

    describe "with a .md URL suffix" do
      before { get "/t/#{topic.slug}/#{topic.id}.md" }

      it "returns a Markdown representation" do
        expect(response.status).to eq(200)
        expect(response.media_type).to eq("text/markdown")
        expect(response.body).to include("# #{topic.title}")
      end

      it "sets X-Robots-Tag: noindex, nofollow so the alias isn't indexed" do
        expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
      end
    end

    describe "HTML response" do
      before { get "/t/#{topic.slug}/#{topic.id}" }

      it "advertises the Markdown sibling via the Link header" do
        expect(response.headers["Link"].to_s).to include("/t/#{topic.slug}/#{topic.id}.md")
        expect(response.headers["Link"].to_s).to include('rel="alternate"')
        expect(response.headers["Link"].to_s).to include('type="text/markdown"')
      end

      it "advertises the Markdown sibling via <link rel='alternate'> in <head>" do
        expect(response.body).to include(
          %(<link rel="alternate" type="text/markdown" href="/t/#{topic.slug}/#{topic.id}.md">),
        )
      end
    end

    describe "permissions" do
      it "returns 404 when the topic is soft-deleted and the user can't see it" do
        topic.trash!
        get "/t/#{topic.slug}/#{topic.id}.md"
        expect(response.status).to eq(404)
      end

      it "does not leak staff-only whisper posts to anonymous readers" do
        SiteSetting.whispers_allowed_groups = "#{Group::AUTO_GROUPS[:staff]}"
        whisper =
          Fabricate(
            :post,
            topic: topic,
            user: Fabricate(:moderator),
            raw: "Mod-only whisper content",
            post_type: Post.types[:whisper],
          )
        Topic.reset_highest(topic.id)

        get "/t/#{topic.slug}/#{topic.id}.md"

        expect(response.status).to eq(200)
        expect(response.body).not_to include(whisper.raw)
        expect(response.body).not_to include("Mod-only whisper content")
        # Count must reflect what the reader can see, not the true total —
        # otherwise the existence of the whisper leaks via the metadata.
        expect(topic.reload.highest_post_number).to be < topic.highest_staff_post_number
        expect(response.body).to include("**Posts:** #{topic.highest_post_number}")
        expect(response.body).not_to include("**Posts:** #{topic.highest_staff_post_number}")
      end
    end
  end

  describe "long topics" do
    it "renders every post in a topic with more than 30 replies" do
      long_topic =
        Fabricate(:topic, user: user, category: category, title: "A fairly long thread for testing")
      Fabricate(:post, topic: long_topic, user: user, raw: "Post 1", post_number: 1)
      2.upto(35) do |n|
        Fabricate(:post, topic: long_topic, user: user, raw: "Post #{n}", post_number: n)
      end

      get "/t/#{long_topic.slug}/#{long_topic.id}.md"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to include("Post 35")
    end
  end

  describe "single post route" do
    fab!(:reply) do
      Fabricate(:post, topic: topic, user: user, raw: "Second post here.", post_number: 2)
    end

    it "renders only the requested post and links back to the full topic" do
      get "/t/#{topic.slug}/#{topic.id}/2.md"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to include("Second post here.")
      expect(response.body).to include("**Showing post:** 2")
      expect(response.body).to include("View the full topic")
      expect(response.body).not_to include("Welcome to the forum.")
    end

    it "returns 404 when the post_number doesn't exist" do
      get "/t/#{topic.slug}/#{topic.id}/999.md"
      expect(response.status).to eq(404)
    end

    it "returns 404 when the requested post exists but the reader can't see it" do
      SiteSetting.whispers_allowed_groups = "#{Group::AUTO_GROUPS[:staff]}"
      whisper =
        Fabricate(
          :post,
          topic: topic,
          user: Fabricate(:moderator),
          raw: "Mod-only whisper content",
          post_type: Post.types[:whisper],
        )

      get "/t/#{topic.slug}/#{topic.id}/#{whisper.post_number}.md"

      expect(response.status).to eq(404)
    end
  end

  describe "list routes" do
    %w[/latest.md /top.md /hot.md].each do |path|
      it "#{path} returns a Markdown topic list" do
        get path
        expect(response.status).to eq(200)
        expect(response.media_type).to eq("text/markdown")
      end
    end
  end

  describe "homepage" do
    it "GET / with Accept: text/markdown returns the configured homepage list" do
      get "/", headers: { "Accept" => "text/markdown" }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/markdown")
    end
  end

  describe "category route" do
    it "/c/:slug/:id.md returns a category topic list" do
      get "/c/#{category.slug}/#{category.id}.md"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to include(category.name)
    end
  end

  describe "tag route" do
    fab!(:tag) { Fabricate(:tag, name: "integration-example") }
    before { topic.tags << tag }

    it "/tag/:tag.md returns a tagged topic list" do
      get "/tag/integration-example.md"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to include("#integration-example")
    end
  end

  describe "user activity route" do
    it "/u/:username/activity.md lists the user's topics" do
      get "/u/#{user.username}/activity.md"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to include("@#{user.username} — Activity")
      expect(response.body).to include(topic.title)
    end
  end

  describe "discovery on non-topic routes" do
    it "advertises /latest.md on the HTML /latest response" do
      get "/latest"
      expect(response.headers["Link"].to_s).to include("/latest.md")
    end

    it "injects an <atom:link> for Markdown into /latest.rss" do
      get "/latest.rss"
      expect(response.body).to include(
        %(<atom:link href="/latest.md" rel="alternate" type="text/markdown" />),
      )
    end
  end

  describe "strict_accept" do
    before { SiteSetting.discourse_to_markdown_strict_accept = true }

    it "returns 406 when Accept excludes both text/html and text/markdown" do
      get "/t/#{topic.slug}/#{topic.id}", headers: { "Accept" => "application/octet-stream" }

      expect(response.status).to eq(406)
      expect(response.body).to include("Available representations: text/html, text/markdown")
    end

    it "still serves Markdown when the URL signals it (.md wins over Accept)" do
      get "/t/#{topic.slug}/#{topic.id}.md", headers: { "Accept" => "application/octet-stream" }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/markdown")
    end

    it "still serves HTML when no Accept header is sent (RFC 9110)" do
      get "/t/#{topic.slug}/#{topic.id}"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end
  end

  describe "plugin disabled" do
    before { SiteSetting.discourse_to_markdown_enabled = false }

    it "does not rewrite .md URLs" do
      get "/t/#{topic.slug}/#{topic.id}.md"
      expect(response.status).to eq(404)
    end

    it "does not flip format on Accept: text/markdown" do
      get "/t/#{topic.slug}/#{topic.id}", headers: { "Accept" => "text/markdown" }
      expect(response.media_type).not_to eq("text/markdown")
    end

    it "does not advertise a Markdown alternate in HTML" do
      get "/t/#{topic.slug}/#{topic.id}"
      expect(response.headers["Link"].to_s).not_to include("text/markdown")
    end
  end
end
