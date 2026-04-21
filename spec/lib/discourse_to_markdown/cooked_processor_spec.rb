# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "nokogiri"
require "reverse_markdown"
require_relative "../../../lib/discourse_to_markdown/cooked_processor"

RSpec.describe DiscourseToMarkdown::CookedProcessor do
  def convert(html)
    described_class.to_markdown(html).strip
  end

  describe "chrome stripping" do
    it "removes div.meta and div.quote-controls" do
      html = <<~HTML
        <p>keep me</p>
        <div class="meta">drop me</div>
        <div class="quote-controls">drop me too</div>
      HTML
      expect(convert(html)).to eq("keep me")
    end
  end

  describe "emojis" do
    it "replaces img.emoji with its :shortcode: from the title" do
      html = %(<p>hi <img class="emoji" title=":wave:" alt=":wave:" src="/wave.png"></p>)
      expect(convert(html)).to eq("hi :wave:")
    end

    it "falls back to alt when title is missing" do
      html = %(<p><img class="emoji" alt=":smile:" src="/smile.png"></p>)
      expect(convert(html)).to eq(":smile:")
    end

    it "does not escape underscores in multi-word shortcodes" do
      html = %(<p><img class="emoji" title=":speaking_head:" src="/speaking_head.png"></p>)
      expect(convert(html)).to eq(":speaking_head:")
    end
  end

  describe "mentions" do
    it "replaces a.mention with @username and strips link markup" do
      html = %(<p>hello <a class="mention" href="/u/alice">@alice</a>!</p>)
      expect(convert(html)).to eq("hello @alice!")
    end
  end

  describe "hashtags" do
    it "replaces a.hashtag / a.hashtag-cooked with #slug" do
      html = <<~HTML
        <p><a class="hashtag" href="/c/general">#general</a>
        <a class="hashtag-cooked" href="/tag/ruby">#ruby</a></p>
      HTML
      expect(convert(html)).to include("#general").and include("#ruby")
    end
  end

  describe "lightboxes" do
    it "unwraps the anchor and swaps the optimized src for the full-size href" do
      html = <<~HTML
        <div class="lightbox-wrapper">
          <a class="lightbox" href="/uploads/full.jpg">
            <img src="/uploads/thumb.jpg" alt="cat">
            <div class="meta">ignored</div>
          </a>
        </div>
      HTML
      expect(convert(html)).to include("![cat](/uploads/full.jpg)")
    end
  end

  describe "quote asides" do
    it "renders a Discourse quote as a Markdown blockquote with attribution" do
      html = <<~HTML
        <aside class="quote" data-username="alice">
          <div class="title">
            <div class="quote-controls"></div>
            <a href="/t/slug/42/3">alice:</a>
          </div>
          <blockquote><p>hello there</p></blockquote>
        </aside>
      HTML
      expect(convert(html)).to include("> [@alice](/t/slug/42/3):").and include("> hello there")
    end
  end

  describe "onebox asides" do
    it "renders onebox as a blockquote with title + source URL + excerpt" do
      html = <<~HTML
        <aside class="onebox">
          <header class="source"><a href="https://example.com">example.com</a></header>
          <article class="onebox-body">
            <h3><a href="https://example.com">Example Title</a></h3>
            <p>Lead excerpt.</p>
          </article>
        </aside>
      HTML
      out = convert(html)
      expect(out).to include("> **[Example Title](https://example.com)**")
      expect(out).to include("> Lead excerpt.")
    end

    it "falls back to a bare URL when no title is present" do
      html = <<~HTML
        <aside class="onebox">
          <header class="source"><a href="https://example.com">example.com</a></header>
        </aside>
      HTML
      expect(convert(html)).to include("> <https://example.com>")
    end
  end

  describe "details" do
    it "renders <details>/<summary> as a blockquoted summary + body" do
      html = <<~HTML
        <details>
          <summary>Click me</summary>
          <p>Hidden body.</p>
        </details>
      HTML
      out = convert(html)
      expect(out).to include("> **Click me**")
      expect(out).to include("> Hidden body.")
    end
  end

  describe "polls" do
    it "renders a minimal stub pointing back to the site" do
      html = %(<div class="poll" data-poll-title="Favorite color?">raw poll HTML</div>)
      expect(convert(html)).to eq("_Poll: Favorite color? (view on site)_")
    end

    it "uses a default title when data-poll-title is missing" do
      html = %(<div class="poll">raw poll HTML</div>)
      expect(convert(html)).to eq("_Poll: Poll (view on site)_")
    end
  end

  describe "ordinary HTML" do
    it "still converts paragraphs, emphasis, and code via reverse_markdown" do
      html = "<p>plain <em>emphatic</em> text with <code>code</code></p>"
      expect(convert(html)).to eq("plain _emphatic_ text with `code`")
    end

    it "preserves links outside of mentions/hashtags" do
      html = %(<p>see <a href="https://example.com">example</a></p>)
      expect(convert(html)).to eq("see [example](https://example.com)")
    end
  end
end
