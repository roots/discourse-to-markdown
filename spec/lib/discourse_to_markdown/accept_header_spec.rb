# frozen_string_literal: true

require_relative "../../../lib/discourse_to_markdown/accept_header"

RSpec.describe DiscourseToMarkdown::AcceptHeader do
  describe ".quality" do
    def q(accept, type = "text", subtype = "markdown")
      described_class.quality(accept, type, subtype)
    end

    context "with blank or missing input" do
      it { expect(q(nil)).to eq(0.0) }
      it { expect(q("")).to eq(0.0) }
      it { expect(q("   ")).to eq(0.0) }
    end

    context "with a single exact match" do
      it "returns 1.0 for an implicit q" do
        expect(q("text/markdown")).to eq(1.0)
      end

      it "returns the explicit q" do
        expect(q("text/markdown;q=0.5")).to eq(0.5)
      end

      it "is case-insensitive on the media type" do
        expect(q("TEXT/MARKDOWN")).to eq(1.0)
      end

      it "tolerates surrounding whitespace" do
        expect(q("  text/markdown ; q=0.8 ")).to eq(0.8)
      end
    end

    context "with wildcards" do
      it "matches text/* against text/markdown" do
        expect(q("text/*;q=0.7")).to eq(0.7)
      end

      it "matches */* against text/markdown" do
        expect(q("*/*;q=0.4")).to eq(0.4)
      end

      it "prefers exact over subtype wildcard regardless of q" do
        # exact match with q=0.3 beats text/* with q=0.9
        expect(q("text/markdown;q=0.3, text/*;q=0.9")).to eq(0.3)
      end

      it "prefers subtype wildcard over full wildcard regardless of q" do
        expect(q("text/*;q=0.3, */*;q=0.9")).to eq(0.3)
      end
    end

    context "with multiple same-specificity entries" do
      it "picks the higher q" do
        expect(q("text/*;q=0.3, text/*;q=0.9")).to eq(0.9)
      end
    end

    context "with q=0 (explicit rejection)" do
      it "returns 0.0 for a rejected exact match even if a wildcard accepts" do
        # RFC 9110: q=0 means "not acceptable"; exact-match specificity wins.
        expect(q("text/markdown;q=0, */*")).to eq(0.0)
      end
    end

    context "with no match" do
      it "returns 0.0 when no entry matches" do
        expect(q("application/json, image/png")).to eq(0.0)
      end
    end

    context "with malformed entries" do
      it "treats empty comma-separated slots as no-ops" do
        expect(q("text/markdown,,text/html")).to eq(1.0)
      end

      it "treats a missing q value as 0.0 (matching PHP (float) cast)" do
        expect(q("text/markdown;q=")).to eq(0.0)
      end

      it "treats a non-numeric q as 0.0" do
        expect(q("text/markdown;q=abc")).to eq(0.0)
      end

      it "ignores entries without a subtype" do
        expect(q("text, text/markdown")).to eq(1.0)
      end

      it "ignores non-q parameters" do
        expect(q("text/markdown;level=2;q=0.6;charset=utf-8")).to eq(0.6)
      end

      it "is case-insensitive on the q parameter" do
        expect(q("text/markdown;Q=0.5")).to eq(0.5)
      end
    end

    context "with the Rails-default Accept header" do
      # The gotcha the plugin exists to fix: Rails' built-in negotiation on
      # `text/markdown, text/html, */*` ties all three at q=1.0 and picks HTML
      # first. Our parser reports markdown and html at the same quality so the
      # controller layer can give markdown the tiebreaker.
      it "reports 1.0 for text/markdown" do
        expect(q("text/markdown, text/html, */*")).to eq(1.0)
      end

      it "reports 1.0 for text/html too" do
        expect(q("text/markdown, text/html, */*", "text", "html")).to eq(1.0)
      end
    end
  end

  describe ".prefers_markdown?" do
    def prefers?(accept)
      described_class.prefers_markdown?(accept)
    end

    it "returns false when the header is missing" do
      expect(prefers?(nil)).to be false
      expect(prefers?("")).to be false
    end

    it "returns true when only text/markdown is accepted" do
      expect(prefers?("text/markdown")).to be true
    end

    it "returns false when only text/html is accepted" do
      expect(prefers?("text/html")).to be false
    end

    it "returns true when markdown's q beats html's" do
      expect(prefers?("text/html;q=0.5, text/markdown;q=0.9")).to be true
    end

    it "returns false when html's q beats markdown's" do
      expect(prefers?("text/html, text/markdown;q=0.5")).to be false
    end

    it "returns false on an explicit tie (Rails-default header)" do
      # Tiebreak for .md URL suffix happens elsewhere; the Accept header
      # alone doesn't flip.
      expect(prefers?("text/markdown, text/html, */*")).to be false
    end

    it "returns false when markdown is explicitly rejected with q=0" do
      expect(prefers?("text/markdown;q=0, text/html")).to be false
    end

    it "returns false when neither type is acceptable" do
      expect(prefers?("application/json")).to be false
    end

    it "returns true when text/* beats html's exact q" do
      # text/* matches markdown at q=0.9 (specificity 1); html specificity 2
      # at q=0.5 still loses because we compare the computed qualities,
      # which are 0.9 vs 0.5.
      expect(prefers?("text/*;q=0.9, text/html;q=0.5")).to be true
    end
  end
end
