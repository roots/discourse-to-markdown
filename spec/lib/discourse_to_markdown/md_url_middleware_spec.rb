# frozen_string_literal: true

unless defined?(SiteSetting)
  module SiteSetting
    @settings = { discourse_to_markdown_enabled: true, discourse_to_markdown_md_urls_enabled: true }

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

require_relative "../../../lib/discourse_to_markdown/md_url_middleware"

RSpec.describe DiscourseToMarkdown::MdUrlMiddleware do
  before do
    SiteSetting.discourse_to_markdown_enabled = true
    SiteSetting.discourse_to_markdown_md_urls_enabled = true
  end

  let(:downstream) { ->(env) { [200, { "Content-Type" => "text/html" }, ["body"]] } }
  let(:middleware) { described_class.new(downstream) }

  def call(path, app: middleware)
    env = { "PATH_INFO" => path }
    status, headers, body = app.call(env)
    { env: env, status: status, headers: headers, body: body }
  end

  describe "with a .md-suffixed path" do
    it "strips the suffix before dispatching to the app" do
      result = call("/t/welcome/5.md")
      expect(result[:env]["PATH_INFO"]).to eq("/t/welcome/5")
    end

    it "sets the env flag so the controller layer can read it" do
      result = call("/t/welcome/5.md")
      expect(result[:env][described_class::ENV_FLAG]).to be true
    end

    it "adds X-Robots-Tag: noindex, nofollow to the response" do
      result = call("/t/welcome/5.md")
      expect(result[:headers]["X-Robots-Tag"]).to eq("noindex, nofollow")
    end

    it "handles root-level .md paths like /latest.md" do
      result = call("/latest.md")
      expect(result[:env]["PATH_INFO"]).to eq("/latest")
    end

    it "strips only one .md suffix (not greedy)" do
      result = call("/foo.md.md")
      expect(result[:env]["PATH_INFO"]).to eq("/foo.md")
    end

    it "does not match /.md (no content before the suffix)" do
      result = call("/.md")
      expect(result[:env]["PATH_INFO"]).to eq("/.md")
      expect(result[:env][described_class::ENV_FLAG]).to be_nil
    end

    it "does not match /foo/.md (empty last segment)" do
      result = call("/foo/.md")
      expect(result[:env]["PATH_INFO"]).to eq("/foo/.md")
      expect(result[:env][described_class::ENV_FLAG]).to be_nil
    end
  end

  describe "with a non-.md path" do
    it "leaves the path untouched" do
      result = call("/t/welcome/5")
      expect(result[:env]["PATH_INFO"]).to eq("/t/welcome/5")
    end

    it "does not set the env flag" do
      result = call("/t/welcome/5")
      expect(result[:env][described_class::ENV_FLAG]).to be_nil
    end

    it "does not add X-Robots-Tag" do
      result = call("/t/welcome/5")
      expect(result[:headers]["X-Robots-Tag"]).to be_nil
    end
  end

  describe "when the plugin is disabled" do
    before { SiteSetting.discourse_to_markdown_enabled = false }

    it "does not rewrite the path" do
      result = call("/t/welcome/5.md")
      expect(result[:env]["PATH_INFO"]).to eq("/t/welcome/5.md")
    end

    it "does not set the env flag" do
      result = call("/t/welcome/5.md")
      expect(result[:env][described_class::ENV_FLAG]).to be_nil
    end
  end

  describe "when .md URLs are disabled but the plugin is enabled" do
    before { SiteSetting.discourse_to_markdown_md_urls_enabled = false }

    it "leaves the .md suffix in place" do
      result = call("/t/welcome/5.md")
      expect(result[:env]["PATH_INFO"]).to eq("/t/welcome/5.md")
      expect(result[:env][described_class::ENV_FLAG]).to be_nil
    end
  end
end
