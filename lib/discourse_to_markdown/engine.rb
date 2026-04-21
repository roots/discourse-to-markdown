# frozen_string_literal: true

module ::DiscourseToMarkdown
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscourseToMarkdown
    config.autoload_paths << File.join(config.root, "lib")
    scheduled_job_dir = "#{config.root}/app/jobs/scheduled"
    config.to_prepare do
      Rails.autoloaders.main.eager_load_dir(scheduled_job_dir) if Dir.exist?(scheduled_job_dir)
    end

    initializer "discourse_to_markdown.md_url_middleware" do |app|
      require_relative "md_url_middleware"
      app.middleware.unshift(::DiscourseToMarkdown::MdUrlMiddleware)
    end
  end
end
