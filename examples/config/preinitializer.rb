ENV['HOME'] = "/home/bkr" if (ENV['HOME'] == "/nonexistent" || ENV['HOME'] == '/' || ENV['HOME'].nil?)
begin
  require "rubygems"
  require "bundler"
#rescue LoadError
#  raise "Could not load the bundler gem. Install it with `gem install bundler`."
end

if Gem::Version.new(Bundler::VERSION) <= Gem::Version.new("0.9.24")
  raise RuntimeError, "Your bundler version is too old." +
   "Run `gem install bundler` to upgrade."
end

begin
  # Set up load paths for all bundled gems
  ENV["BUNDLE_GEMFILE"] = File.expand_path("../../Gemfile", __FILE__)
  Bundler.setup(:default, :cart, (ENV['RAILS_ENV'] || 'development').to_sym)
rescue Bundler::GemNotFound
  raise RuntimeError, "Bundler couldn't find some gems." +
    "Did you run `bundle install`?"
end