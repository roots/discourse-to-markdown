# frozen_string_literal: true

module DiscourseToMarkdown
  module AcceptHeader
    class << self
      # Returns the q-value for `type/subtype` in the given Accept header,
      # using the q of the most specific matching entry (exact > type/* >
      # */*) per RFC 9110 §12.5.1. Returns 0.0 when nothing matches or the
      # header is blank.
      #
      # Specificity beats q: `text/markdown;q=0.3, text/*;q=0.9` returns 0.3
      # for text/markdown, because the exact match wins regardless of q.
      def quality(accept, type, subtype)
        return 0.0 if accept.nil? || accept.strip.empty?

        best = accept.split(",").filter_map { |e| match_entry(e, type, subtype) }.max

        best ? best.last : 0.0
      end

      # Returns true when the client prefers text/markdown over text/html
      # based on the Accept header alone. Strictly greater: ties fall
      # through to false so HTML (the historical default) wins on its own.
      # The .md URL-suffix flip happens elsewhere.
      def prefers_markdown?(accept)
        markdown = quality(accept, "text", "markdown")
        markdown.positive? && markdown > quality(accept, "text", "html")
      end

      private

      def match_entry(entry, type, subtype)
        entry = entry.strip
        return nil if entry.empty?

        media_type, *params = entry.split(";")
        t, s = media_type.to_s.strip.downcase.split("/", 2)
        return nil if t.nil? || s.nil?

        specificity =
          if t == type && s == subtype
            2
          elsif t == type && s == "*"
            1
          elsif t == "*" && s == "*"
            0
          else
            return nil
          end

        q = 1.0
        params.each do |param|
          param = param.strip
          q = param[2..].to_f if param.downcase.start_with?("q=")
        end

        [specificity, q]
      end
    end
  end
end
