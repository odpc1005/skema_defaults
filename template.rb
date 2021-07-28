require "fileutils"
require "shellwords"

# Copied from: https://github.com/mattbrictson/rails-template
def add_template_repository_to_source_path
  if __FILE__ =~ %r{\Ahttps?://}
    require "tmpdir"
    source_paths.unshift(tempdir = Dir.mktmpdir("skema-defaults"))
    at_exit { FileUtils.remove_entry(tempdir) }
    git clone: [
      "--quiet",
      "https://github.com/odpc1005/skema_defaults.git",
      tempdir
    ].map(&:shellescape).join(" ")

    if (branch = __FILE__[%r{skema_defaults/(.+)/template.rb}, 1])
      Dir.chdir(tempdir) { git checkout: branch }
    end
  else
    source_paths.unshift(File.dirname(__FILE__))
  end
end

def rails_version
  @rails_version ||= Gem::Version.new(Rails::VERSION::STRING)
end

def rails_5?
  Gem::Requirement.new(">= 5.2.0", "< 6.0.0.beta1").satisfied_by? rails_version
end

def rails_6?
  Gem::Requirement.new(">= 6.0.0.alpha", "< 7").satisfied_by? rails_version
end

def rails_7?
  Gem::Requirement.new(">= 7.0.0.alpha", "< 8").satisfied_by? rails_version
end

def master?
  ARGV.include? "--master"
end

def add_gems
  gem 'bootstrap', '5.0.0'
  if rails_7? || master?
    gem "devise", github: "ghiculescu/devise", branch: "patch-2"
  else
    gem 'devise', '~> 4.8', '>= 4.8.0'
  end
  gem 'devise_masquerade', '~> 1.3'
  gem 'font-awesome-sass', '~> 5.15'
  gem 'image_processing'
  gem 'madmin'
  gem 'mini_magick', '~> 4.10', '>= 4.10.1'
  gem 'name_of_person', '~> 1.1'
  gem 'noticed', '~> 1.2'
  gem 'pundit', '~> 2.1'
  gem 'redis', '~> 4.2', '>= 4.2.2'
  gem 'sidekiq', '~> 6.2'
  gem 'sitemap_generator', '~> 6.1', '>= 6.1.2'
end

def set_application_name
  # Add Application Name to Config
  if rails_5?
    environment "config.application_name = Rails.application.class.parent_name"
  else
    environment "config.application_name = Rails.application.class.module_parent_name"
  end

  # Announce the user where they can change the application name in the future.
  puts "You can change application name inside: ./config/application.rb"
end

def add_users
  route "root to: 'home#index'"
  generate "devise:install"
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: 'development'
  generate :devise, "User", "first_name", "last_name", "announcements_last_read_at:datetime", "admin:boolean"

  # Set admin default to false
  in_root do
    migration = Dir.glob("db/migrate/*").max_by{ |f| File.mtime(f) }
    gsub_file migration, /:admin/, ":admin, default: false"
  end

  if Gem::Requirement.new("> 5.2").satisfied_by? rails_version
    gsub_file "config/initializers/devise.rb", /  # config.secret_key = .+/, "  config.secret_key = Rails.application.credentials.secret_key_base"
  end

  # Add Devise masqueradable to users
  inject_into_file("app/models/user.rb", "masqueradable, :", after: "devise :")
end

def add_authorization
  generate 'pundit:install'
end

def add_javascript
  run "yarn add expose-loader @popperjs/core bootstrap local-time"

  if rails_5?
    run "yarn add turbolinks @rails/actioncable@pre @rails/actiontext@pre @rails/activestorage@pre @rails/ujs@pre"
  end

  content = <<-JS
const webpack = require('webpack')
environment.plugins.append('Provide', new webpack.ProvidePlugin({
  Rails: '@rails/ujs'
}))
  JS

  insert_into_file 'config/webpack/environment.js', content + "\n", before: "module.exports = environment"
end

def copy_templates
  #remove_file "app/assets/stylesheets/application.css"

  #copy_file "Procfile"
  #copy_file "Procfile.dev"
  #copy_file ".foreman"

  #directory "app", force: true
  #directory "config", force: true
  directory "lib", force: true

  #route "get '/terms', to: 'home#terms'"
  #route "get '/privacy', to: 'home#privacy'"
end

def add_sidekiq
  environment "config.active_job.queue_adapter = :sidekiq"

  insert_into_file "config/routes.rb",
    "require 'sidekiq/web'\n\n",
    before: "Rails.application.routes.draw do"

  content = <<~RUBY
                authenticate :user, lambda { |u| u.admin? } do
                  mount Sidekiq::Web => '/sidekiq'
                  namespace :madmin do
                  end
                end
            RUBY
  insert_into_file "config/routes.rb", "#{content}\n", after: "Rails.application.routes.draw do\n"
end


def stop_spring
  run "spring stop"
end

# Main setup
add_template_repository_to_source_path

add_gems

after_bundle do
  set_application_name
  puts "application name set"
  sleep 10
  stop_spring
  add_users
  puts "users added"
  sleep 10
  add_authorization
  puts "authorization added"
  sleep 10
  add_javascript
  puts "js added"
  sleep 10
  add_sidekiq
  puts "sidekiq added"
  sleep 10
  copy_templates
  puts "templates copied"
  sleep 10

  rails_command "active_storage:install"
  puts "active storage intalled"
  sleep 10

  # Commit everything to git
  unless ENV["SKIP_GIT"]
    git :init
    git add: "."
    # git commit will fail if user.email is not configured
    begin
      git commit: %( -m 'Initial commit' )
    rescue StandardError => e
      puts e.message
    end
  end

  say
  say "App successfully created!", :blue
  say
  say "To get started with your new app:", :green
  say "  cd #{app_name}"
  say
  say "  # Update config/database.yml with your database credentials"
  say
  say "  rails db:create db:migrate"
  say "  rails g madmin:install # Generate admin dashboards"
end
