# frozen_string_literal: true

module DiscourseToMarkdown
  class CookedProcessor
    BLOCK_TAG = "dtm-block"
    INLINE_TAG = "dtm-inline"

    class PreservedBlockConverter < ReverseMarkdown::Converters::Base
      def convert(node, _state = {})
        "\n\n#{node.text}\n\n"
      end
    end

    class PreservedInlineConverter < ReverseMarkdown::Converters::Base
      def convert(node, _state = {})
        node.text
      end
    end

    ReverseMarkdown::Converters.register(BLOCK_TAG.to_sym, PreservedBlockConverter.new)
    ReverseMarkdown::Converters.register(INLINE_TAG.to_sym, PreservedInlineConverter.new)

    def self.to_markdown(cooked_html)
      new(cooked_html).to_markdown
    end

    def initialize(cooked_html)
      @fragment = Nokogiri::HTML5.fragment(cooked_html.to_s)
    end

    def to_markdown
      strip_chrome
      replace_emojis
      replace_mentions
      replace_hashtags
      replace_lightboxes
      replace_quotes
      replace_oneboxes
      replace_details
      replace_polls

      ReverseMarkdown.convert(@fragment.to_html, github_flavored: true, unknown_tags: :bypass)
    end

    private

    def strip_chrome
      @fragment.css("div.meta, div.quote-controls").each(&:remove)
    end

    def replace_emojis
      @fragment
        .css("img.emoji")
        .each { |img| img.replace(preserved_inline(img["title"] || img["alt"] || "")) }
    end

    def replace_mentions
      @fragment
        .css("a.mention")
        .each do |anchor|
          username = anchor.text.to_s.delete_prefix("@")
          anchor.replace(preserved_inline("@#{username}"))
        end
    end

    def replace_hashtags
      @fragment
        .css("a.hashtag, a.hashtag-cooked")
        .each do |anchor|
          slug = anchor.text.to_s.delete_prefix("#")
          anchor.replace(preserved_inline("##{slug}"))
        end
    end

    def replace_lightboxes
      @fragment
        .css("a.lightbox")
        .each do |anchor|
          img = anchor.at_css("img")
          next anchor.remove unless img

          img["src"] = anchor["href"] if anchor["href"]
          anchor.replace(img)
        end

      @fragment
        .css("div.lightbox-wrapper")
        .each do |wrapper|
          inner = wrapper.at_css("img, picture")
          inner ? wrapper.replace(inner) : wrapper.remove
        end
    end

    def replace_quotes
      @fragment
        .css("aside.quote")
        .each do |aside|
          attribution = aside.at_css(".title a")
          user_label =
            attribution&.text&.strip&.delete_suffix(":").presence || aside["data-username"].to_s
          post_url = attribution&.[]("href") || "#"

          body_md = convert_inner(aside.at_css("blockquote"))

          lines = ["> [@#{user_label}](#{post_url}):", ">"]
          body_md.each_line { |line| lines << "> #{line.chomp}" }

          aside.replace(preserved_block(lines.join("\n")))
        end
    end

    def replace_oneboxes
      @fragment
        .css("aside.onebox")
        .each do |aside|
          title_link = aside.at_css("h3 a")
          title = title_link&.text&.strip
          url =
            title_link&.[]("href") || aside.at_css("header.source a")&.[]("href") ||
              aside.at_css("article a")&.[]("href")
          excerpt = aside.at_css("article.onebox-body p, .onebox-body p")&.text&.strip

          lines = []
          if title && !title.empty? && url
            lines << "> **[#{title}](#{url})**"
          elsif url
            lines << "> <#{url}>"
          end

          if excerpt && !excerpt.empty?
            lines << ">"
            excerpt.each_line { |line| lines << "> #{line.chomp}" }
          end

          lines.empty? ? aside.remove : aside.replace(preserved_block(lines.join("\n")))
        end
    end

    def replace_details
      @fragment
        .css("details")
        .each do |details|
          summary = details.at_css("summary")&.text&.strip.to_s
          body_html = details.children.reject { |n| n.name == "summary" }.map(&:to_html).join
          body_md =
            ReverseMarkdown.convert(body_html, github_flavored: true, unknown_tags: :bypass).strip

          lines = ["> **#{summary}**", ">"]
          body_md.each_line { |line| lines << "> #{line.chomp}" }

          details.replace(preserved_block(lines.join("\n")))
        end
    end

    def replace_polls
      @fragment
        .css("div.poll")
        .each do |poll|
          title =
            poll["data-poll-title"].presence ||
              poll.at_css("[data-poll-title]")&.[]("data-poll-title").presence || "Poll"

          poll.replace(preserved_block("_Poll: #{title} (view on site)_"))
        end
    end

    def convert_inner(node)
      return "" unless node

      ReverseMarkdown.convert(node.inner_html, github_flavored: true, unknown_tags: :bypass).strip
    end

    def preserved_inline(content)
      node = Nokogiri::XML::Node.new(INLINE_TAG, @fragment.document)
      node.content = content
      node
    end

    def preserved_block(markdown)
      node = Nokogiri::XML::Node.new(BLOCK_TAG, @fragment.document)
      node.content = markdown
      node
    end
  end
end
